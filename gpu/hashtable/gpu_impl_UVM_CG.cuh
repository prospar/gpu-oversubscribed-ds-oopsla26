#include <algorithm>
#include <cooperative_groups.h>
#include <cstdint>
#include <cstring>
#include <cuda.h>

#include "constants.h"
#include "datatypes.h"
#include "functions.h"
#include "global-vars.h"

namespace cg = cooperative_groups;

__global__ void initialize_hash(KeyValue *hashtable, uint64_t capacity) {
  uint64_t tid = blockIdx.x * blockDim.x + threadIdx.x;
  if (tid < capacity) {
    hashtable[tid].key = SENTINEL_KEY;
    hashtable[tid].value = SENTINEL_VALUE;
  }
}

// FIXME: SB: This function is duplicated in gpu_part_batch.cuh. Move the
// function to common file and add flag for type of memory allocation.
KeyValue *creategpuHash_UVM(uint64_t size) {
  cout << "Size of HT to be created: " << size << "\n";
  KeyValue *hashTable = nullptr;
  cudaCheckErrorMacro(cudaMallocManaged(&hashTable, sizeof(KeyValue) * size),
                      "Memory allocation for the hashtable failed");

  return hashTable;
}

__device__ uint32_t lookupgpuimpl_CG(
    KeyValue *hashTable, uint32_t key, uint64_t capacity, uint32_t rand_int,
    uint64_t primeDH, const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint64_t pos = 0;
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
  pos = group.thread_rank();
#else
  if (primeDH > COOP_GROUP_SIZE)
    pos = COOP_GROUP_SIZE;
#endif
  uint64_t i = 0;
#if defined(HH)
  i = ((hashFuncIdentity(key) % capacity) + group.thread_rank()) % capacity;
#elif defined(SH)
  i = (hashFuncSH(key, rand_int) + group.thread_rank()) % capacity;
#elif defined(MM)
  i = (hashFuncWC(key) + group.thread_rank()) % capacity;
#else
  i = (((uint64_t)key * 11400714819323198485) + group.thread_rank()) % capacity;
#endif
  uint64_t secondary_hash = primeDH;

  while (i < ~uint32_t(0)) {
    // printf("The value of i is %ld\n", i);
    uint32_t key_p = hashTable[i].key;
    const bool hit = (key_p == key);
    const auto hitmask = group.ballot(hit);
    if (hitmask) {
      const auto leader = __ffs(hitmask) - 1;
      const auto leader_index = group.shfl(i, leader);
      return hashTable[leader_index].value;
    }
    if (group.any(key_p == SENTINEL_KEY)) {
      return 0;
    }
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
    pos += COOP_GROUP_SIZE;
#else
    pos++;
#endif
#if defined(QUADRATIC_PROBING)
    i = ((i * i) + COOP_GROUP_SIZE) % capacity;
#elif defined(LINEAR_PROBING)
    i = (i + COOP_GROUP_SIZE) % capacity;
#else
    i = (i + secondary_hash) % capacity;
#endif
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
    if (pos >= inner_table_capacity)
      i = ~uint64_t(0);
#else
    if (primeDH <= COOP_GROUP_SIZE && pos >= (capacity / primeDH) + 1) {
      // If the primeDH is less than or equal to cooperative group size then we can gurantee that
      // the probing is done for all the slots.
      i = ~uint64_t(0);
    } else if (pos >= capacity)
      // If the primeDH is more than cooperative group size then we can gurantee that the probing
      // is done for all the slots only if it runs for the entire capacity.
      i = ~uint64_t(0);
#endif
  }
  return 0;
}

__global__ void batch_lookup_gpu_kernel_CG(KeyValue *hashtable,
                                           uint32_t *d_keys,
                                           uint32_t *searched_value,
                                           uint64_t num_queries,
                                           uint64_t capacity, uint32_t rand_int,
                                           uint64_t primeDH) {
  uint64_t tid = blockDim.x * blockIdx.x + threadIdx.x;
  size_t gid = tid / COOP_GROUP_SIZE;
  const auto group =
      cg::tiled_partition<COOP_GROUP_SIZE>(cg::this_thread_block());

  if (gid < num_queries) {
    uint32_t value;
    value = lookupgpuimpl_CG(hashtable, d_keys[gid], capacity, rand_int,
                             primeDH, group);
    if (group.thread_rank() == 0) {
      if (value != 0) {
        searched_value[gid] = value;
      }
    }
  }
}

/** Called by the driver. */
float batch_lookup_gpu_UVM_CG(KeyValue *mHashTable, uint32_t *search_queries,
                              uint32_t *searched_values, uint64_t num_queries,
                              uint64_t capacity) {
  uint64_t num_blocks = SDIV((num_queries * COOP_GROUP_SIZE), BlockSize);
#if defined(GPU_DEBUG) || defined(DEBUG)
  printf("HASHTABLE: launching search kernel on GPU\n");
#endif
  uint32_t rand_int = 0;
#if defined(SH)
  std::mt19937 rng(0);
  rand_int = rng() % PRIME_DIVISOR;
#endif
  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  cudaEventRecord(start, 0);

  batch_lookup_gpu_kernel_CG<<<num_blocks, BlockSize>>>(
      mHashTable, search_queries, searched_values, num_queries, capacity,
      rand_int, smallerPrimeGPU);

  cudaEventRecord(stop, 0);
  cudaEventSynchronize(stop);
  cudaCheckErrorMacro(cudaGetLastError(), "Search kernel failure");

  float elapsedTime = 0.0f;
  cudaEventElapsedTime(&elapsedTime, start, stop);

#if defined(GPU_DEUBG)
  printf("HASHTABLE: search kernel complete\n");
#endif
  return elapsedTime;
}

__device__ uint32_t *
insertgpuimpl_CG(uint32_t key, KeyValue *hashtable, uint64_t capacity,
                 uint64_t maxCollisions, uint32_t rand_int, uint64_t primeDH,
                 const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint64_t pos = 0;
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
  pos = group.thread_rank();
#else
  if (primeDH > COOP_GROUP_SIZE)
    pos = group.thread_rank();
#endif
  uint64_t i = 0;
#if defined(HH)
  i = (((hashFuncIdentity(key) % capacity) + group.thread_rank()) % capacity);
#elif defined(SH)
  i = (hashFuncSH(key, rand_int) + group.thread_rank()) % capacity;
#elif defined(MM)
  i = (hashFuncMurmur(key) + group.thread_rank()) % capacity;
#else
  i = (((uint64_t)key * 11400714819323198485) + group.thread_rank()) % capacity;
#endif
  uint64_t secondary_hash = primeDH;

#if defined(GPU_DEBUG)
  assert(secondary_hash > 0);
#endif

#ifdef STATS
  __shared__ uint32_t c;
  c = 0;
#endif

  // std::numeric_limits<uint64_t>::max() is same as (uint64_t)~0
  while (i < ~uint64_t(0)) {
    uint32_t key_p = hashtable[i].key;
    const bool hit = (key_p == key);
    const auto hitmask = group.ballot(hit);
    if (hitmask) {
      const auto leader = __ffs(hitmask) - 1;
      const auto leader_index = group.shfl(i, leader);
      // printf("The leader index in hitmask %d\n", leader_index);

#ifdef STATS
      if (group.thread_rank() == leader)
        printf("The collision count(from hit) is %d\n", c);
#endif
#if defined(INSERT_DEBUG)
      printf("The leader index in hitmask %ld and key is: %d\n", leader_index,
             hashtable[leader_index].key);
#endif // INSERT_DEBUG
      return (&hashtable[leader_index].value);
    }

    auto empty_mask = group.ballot((key_p == SENTINEL_KEY));
    bool success = false;
    bool duplicate = false;

    while (empty_mask) {
      // At least one thread in the warp has found an empty slot
      const auto leader = __ffs(empty_mask) - 1;
      if (group.thread_rank() == leader) {
        const auto old = atomicCAS(&(hashtable[i].key), key_p, key);
        success = (old == key_p);
        duplicate = (old == key);
      }

      if (group.any(duplicate)) {
        const auto leader_index = group.shfl(i, leader);
#if defined(INSERT_DEBUG)
        printf("Duplicate key is: %u\n", hashtable[leader_index].key);
#endif // INSERT_DEBUG

#ifdef STATS
        if (group.thread_rank() == leader)
          printf("The collision count(from duplicate) is %d\n", c);
#endif
        return (&hashtable[leader_index].value);
      }

      if (group.any(success)) {
        const auto leader_index = group.shfl(i, leader);
#if defined(INSERT_DEBUG)
        printf("The leader index in success %ld and key is: %d\n", leader_index,
               hashtable[leader_index].key);
#endif // INSERT_DEBUG
#ifdef STATS
        if (group.thread_rank == leader)
          printf("The collision count(from success) is %d\n", c);
#endif
        return (&hashtable[leader_index].value);
      }
#ifdef STATS
      if (group.thread_rank() == leader)
        atomicInc(&c, maxCollisions);
#endif
      empty_mask ^= 1UL << leader;
    }
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
    pos += COOP_GROUP_SIZE;
#else
    pos++;
#endif
#if defined(QUADRATIC_PROBING)
    i = ((i * i) + COOP_GROUP_SIZE) % capacity;
#elif defined(LINEAR_PROBING)
    i = (i + COOP_GROUP_SIZE) % capacity;

#else
    i = (i + secondary_hash) % capacity;
#endif
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
    if (pos >= capacity)
      i = ~uint64_t(0);
#else
    if (primeDH <= COOP_GROUP_SIZE && pos >= (capacity / primeDH) + 1) {
      // If the primeDH is less than or equal to cooperative group size then we can gurantee that
      // the probing is done for all the slots.
      i = ~uint64_t(0);
    } else if (pos >= capacity)
      // If the primeDH is more than cooperative group size then we can gurantee that the probing
      // is done for all the slots only if it runs for the entire capacity.
      i = ~uint64_t(0);
#endif
  }
  return NULL;
}

// FIXME: SB: Can we eliminate redundant or unused formal arguments?
/** A warp is processing a single insert. */
__global__ void batch_insert_gpu_kernel_CG(KeyValue *hashtable,
                                           KeyValue *kvs_array,
                                           uint64_t gpu_ins, uint64_t capacity,
                                           uint64_t maxCollisions,
                                           uint32_t rand_int,
                                           uint64_t primeDH) {
  size_t tid = (size_t)blockDim.x * blockIdx.x + threadIdx.x;
  size_t gid = tid / COOP_GROUP_SIZE;
  const auto group =
      cg::tiled_partition<COOP_GROUP_SIZE>(cg::this_thread_block());
#if defined(INSERT_DEBUG)
  if (group.thread_rank() == 0) {
    printf("Wid %lu inserting key: %u\n", wid, kvs_array[wid].key);
  }
#endif // INSERT_DEBUG
  // FIXME: SB: Avoid an extra call.
  if (gid < gpu_ins) {
    uint32_t *value_addr =
        insertgpuimpl_CG(kvs_array[gid].key, hashtable, capacity, maxCollisions,
                         rand_int, primeDH, group);
    if (group.thread_rank() == 0 && value_addr != NULL) {
      *value_addr = kvs_array[gid].value;
    }
  }
}

/** Called by the driver */
float batch_insert_gpu_UVM_CG(KeyValue *uvm_hashtable, KeyValue *uvm_kvpairs,
                              uint64_t num_ins, uint64_t capacity) {
  // Each warp inserts one element
  uint64_t num_blocks = SDIV((num_ins * COOP_GROUP_SIZE), BlockSize);
  uint32_t rand_int = 0;
#if defined(SH)
  std::mt19937 rng(0);
  rand_int = rng() % PRIME_DIVISOR;
#endif

#ifdef DEBUG
  printf("HASHTABLE: launching kernel for bulk insert\n");
#endif

  uint64_t maxCollisions = num_ins * (num_ins - 1) / 2 + 1;

  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  cudaEventRecord(start, 0);

  batch_insert_gpu_kernel_CG<<<num_blocks, BlockSize>>>(
      uvm_hashtable, uvm_kvpairs, num_ins, capacity, maxCollisions, rand_int,
      smallerPrimeGPU);

  cudaEventRecord(stop, 0);
  cudaEventSynchronize(stop);
  cudaCheckErrorMacro(cudaGetLastError(), "Insert kernel failure");
  float elapsedTime = 0.0f;
  cudaEventElapsedTime(&elapsedTime, start, stop);

#if defined(GPU_DEBUG)
  printf("HASHTABLE: GPU-batch insertion successful\n");
  printf("Deallocation of memory successful\n");
#endif
  return elapsedTime;
}

__device__ bool
batchdeleteimpl_CG(KeyValue *hashTable, uint32_t key, uint64_t capacity,
                   uint32_t rand_int, uint64_t primeDH,
                   const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint64_t pos = 0;
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
  pos = group.thread_rank();
#else
  if (primeDH > COOP_GROUP_SIZE)
    pos = group.thread_rank();
#endif
  uint64_t i = 0;
#if defined(HH)
  i = (((hashFuncIdentity(key) % capacity) + group.thread_rank()) % capacity);
#elif defined(SH)
  i = (hashFuncSH(key, rand_int) + group.thread_rank()) % capacity;
#elif defined(MM)
  i = (hashFuncMurmur(key) + group.thread_rank()) % capacity;
#else
  i = (((uint64_t)key * 11400714819323198485) + group.thread_rank()) % capacity;
#endif
  uint64_t secondary_hash = primeDH;

  while (i < ~uint32_t(0)) {
    uint32_t key_p = hashTable[i].key;
    bool hit = (key_p == key);
    uint32_t hitmask = group.ballot(hit);
    if (hitmask) {
      uint32_t leader = __ffs(hitmask) - 1;
      // uint32_t leader_index = group.shfl(i, leader);
#ifdef GPU_DEBUG
      printf("The deleted value is %d\n", hashTable[leader_index].value);
#endif
      if (group.thread_rank() == leader) {
        // printf("The key to delete is %u and the key present is: %u and the "
        //        "deleted value is %u\n",
        //  key, key_p, hashTable[leader_index].value);
        hashTable[i].key = TOMBSTONE_KEY;
        hashTable[i].value = TOMBSTONE_VALUE;
      }
      return true;
    }
    if (group.any((key_p == SENTINEL_KEY))) {
      return false;
    }
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
    pos += COOP_GROUP_SIZE;
#else
    pos++;
#endif
#if defined(QUADRATIC_PROBING)
    i = ((i * i) + COOP_GROUP_SIZE) % capacity;
#elif defined(LINEAR_PROBING)
    i = (i + COOP_GROUP_SIZE) % capacity;
#else
    i = (i + secondary_hash) % capacity;
#endif
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
    if (pos >= capacity)
      i = ~uint32_t(0);
#else
    if (primeDH <= COOP_GROUP_SIZE && pos >= (capacity / primeDH) + 1) {
      // If the primeDH is less than or equal to cooperative group size then we can gurantee that
      // the probing is done for all the slots.
      i = ~uint32_t(0);
    } else if (pos >= capacity)
      // If the primeDH is more than cooperative group size then we can gurantee that the probing
      // is done for all the slots only if it runs for the entire capacity.
      i = ~uint32_t(0);
#endif
  }
  return false;
}

__global__ void batch_delete_gpu_kernel_CG(KeyValue *hashTable, uint32_t *keys,
                                           bool *delete_status,
                                           uint64_t num_queries,
                                           uint64_t capacity, uint32_t rand_int,
                                           uint64_t primeDH) {
  size_t tid = (size_t)blockDim.x * blockIdx.x + threadIdx.x;
  size_t gid = tid / COOP_GROUP_SIZE;
  const auto group =
      cg::tiled_partition<COOP_GROUP_SIZE>(cg::this_thread_block());

  if (gid < num_queries) {
    bool del;
    del = batchdeleteimpl_CG(hashTable, keys[gid], capacity, rand_int, primeDH,
                             group);
    if (group.thread_rank() == 0) {
      if (del == true) {
        delete_status[gid] = del;
        // printf("Delete status: %u\n", delete_status[wid]);
      }
    }
  }
}

/** Called by the driver */
float batch_delete_gpu_UVM_CG(KeyValue *mHashtable, uint32_t *del_keys,
                              bool *deleted_result, uint64_t num_queries,
                              uint64_t capacity) {
  uint64_t num_blocks = SDIV((num_queries * COOP_GROUP_SIZE), BlockSize);
  uint32_t rand_int = 0;

#if defined(SH)
  std::mt19937 rng(0);
  rand_int = rng() % PRIME_DIVISOR;
#endif

#if defined(GPU_DEBUG) || defined(DEBUG)
  printf("HASHTABLE: batch deletion call\n");
#endif
#ifdef DELETE_KEY
  printf("Keys to delete:\n");
  for (int index = 0; index < num_queries; index++)
    printf("%u ", h_kvs[index]);
  printf("\n");
#endif

  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  cudaEventRecord(start, 0);

  batch_delete_gpu_kernel_CG<<<num_blocks, BlockSize>>>(
      mHashtable, del_keys, deleted_result, num_queries, capacity, rand_int,
      smallerPrimeGPU);

  cudaEventRecord(stop, 0);
  cudaEventSynchronize(stop);
  cudaCheckErrorMacro(cudaGetLastError(), "Delete kernel failure");
  float elapsedTime = 0.0f;
  cudaEventElapsedTime(&elapsedTime, start, stop);

#if defined(GPU_DEBUG)
  printf("HASHTABLE: delete GPU kernel call successfull\n");
  printf("HASHTABLE: deletion successfull, memory reclaimed from GPU\n");
#endif

  return elapsedTime;
}

__global__ void print_Kernel(KeyValue *hashTable, uint64_t capacity) {
  uint64_t tid = (uint64_t)blockDim.x * blockIdx.x + threadIdx.x;
  if (tid == 0) {
    // uint64_t count = 0;
    for (uint64_t i = 0; i < capacity; i++) {
      if (hashTable[i].key != SENTINEL_KEY &&
          hashTable[i].value != SENTINEL_VALUE &&
          hashTable[i].key != TOMBSTONE_KEY &&
          hashTable[i].value != TOMBSTONE_VALUE) {
        // count++;
        printf("K: %d  V: %d at slot %ld\n", hashTable[i].key,
               hashTable[i].value, i);
      }
    }
    // printf("count is %ld\n", count);
  }
}

void print_gpuHashTable(KeyValue *mHashTable, uint64_t capacity) {
  printf("GPU hashtable\n");
  print_Kernel<<<1, BlockSize>>>(mHashTable, capacity);
  cudaDeviceSynchronize();
}

void Key_Check_GPU(KeyValue *hashTable, uint64_t totalInsert, KeyValue *Kvs,
                   uint64_t gpuHTSize) {
  uint64_t capacity = gpuHTSize;
  std::cout << "HT Capacity: " << capacity << "\n";

  // Collect valid entries from hashTable (key > 0)
  std::vector<KeyValue> ht_entries;
  ht_entries.reserve(capacity);
  for (uint64_t i = 0; i < capacity; i++) {
    if (hashTable[i].key != 0) {
      ht_entries.push_back(hashTable[i]);
    }
  }
  std::cout << "Total inserts: " << totalInsert
            << " Keys inserted in hashtable: " << ht_entries.size() << "\n";

  // Copy inserted keys and values
  std::vector<KeyValue> ins_entries(Kvs, Kvs + totalInsert);

  // Sort both vectors by key only
  std::sort(ht_entries.begin(), ht_entries.end(), compareByKey);
  std::sort(ins_entries.begin(), ins_entries.end(), compareByKey);

  // Optional: remove duplicates from ins_entries if needed
  auto last = std::unique(
      ins_entries.begin(), ins_entries.end(),
      [](const KeyValue &a, const KeyValue &b) { return a.key == b.key; });
  ins_entries.erase(last, ins_entries.end());

  // Compare sizes first
  if (ht_entries.size() != ins_entries.size()) {
    std::cout << "Mismatch in number of valid entries: hashtable "
              << ht_entries.size() << " vs inserted " << ins_entries.size()
              << "\n";
  }

  // Compare element-wise by key only
  uint64_t total_mismatches = 0;
  uint64_t limit = std::min(ht_entries.size(), ins_entries.size());
  for (uint64_t i = 0; i < limit; i++) {
    if (ht_entries[i].key != ins_entries[i].key) {
      total_mismatches++;
      std::cout << "Key mismatch at index " << i << ": HT key("
                << ht_entries[i].key << ") vs Inserted key("
                << ins_entries[i].key << ")\n";
    }
  }
  std::cout << "Total key mismatches: " << total_mismatches << "\n";
}
