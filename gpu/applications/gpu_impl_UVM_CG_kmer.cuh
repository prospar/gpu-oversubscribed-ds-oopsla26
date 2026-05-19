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
                 uint64_t primeDH,
                 const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint64_t pos = 0;
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
  pos = group.thread_rank();
#else
  if (primeDH > COOP_GROUP_SIZE)
    pos = group.thread_rank();
#endif
  uint64_t i = 0;
  i = (((uint64_t)key * 11400714819323198485) + group.thread_rank()) % capacity;

  uint64_t secondary_hash = primeDH;

  // std::numeric_limits<uint64_t>::max() is same as (uint64_t)~0
  while (i < ~uint64_t(0)) {
    uint32_t key_p = hashtable[i].key;
    const bool hit = (key_p == key);
    const auto hitmask = group.ballot(hit);
    if (hitmask) {
      const auto leader = __ffs(hitmask) - 1;
      const auto leader_index = group.shfl(i, leader);
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
        return (&hashtable[leader_index].value);
      }

      if (group.any(success)) {
        const auto leader_index = group.shfl(i, leader);
        return (&hashtable[leader_index].value);
      }
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
                                           uint64_t primeDH) {
  size_t tid = (size_t)blockDim.x * blockIdx.x + threadIdx.x;
  size_t gid = tid / COOP_GROUP_SIZE;
  const auto group =
      cg::tiled_partition<COOP_GROUP_SIZE>(cg::this_thread_block());
  if (gid < gpu_ins) {
    uint32_t *value_addr = insertgpuimpl_CG(kvs_array[gid].key, hashtable,
                                            capacity, primeDH, group);
    if (group.thread_rank() == 0 && value_addr != NULL) {
      atomicAdd(value_addr, 1);
    }
  }
}

/** Called by the driver */
float batch_insert_gpu_UVM_CG(KeyValue *uvm_hashtable, KeyValue *uvm_kvpairs,
                              uint64_t num_ins, uint64_t capacity) {
  // Each warp inserts one element
  uint64_t num_blocks = SDIV((num_ins * COOP_GROUP_SIZE), BlockSize);

  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  cudaEventRecord(start, 0);

  batch_insert_gpu_kernel_CG<<<num_blocks, BlockSize>>>(
      uvm_hashtable, uvm_kvpairs, num_ins, capacity, smallerPrimeGPU);

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
