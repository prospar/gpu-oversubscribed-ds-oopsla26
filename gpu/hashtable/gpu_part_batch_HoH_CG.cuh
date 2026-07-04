#pragma once

#include <algorithm>
#include <cooperative_groups.h>
#include <cstdint>
#include <cuda.h>
#include <cuda_runtime.h>
#include <stdint.h>
#include <unordered_set>

#include "constants.h"
#include "datatypes.h"
#include "functions.h"
#include "global-vars.h"

namespace cg = cooperative_groups;

using std::cout;
using std::endl;
using std::string;
using std::vector;

using std::chrono::duration_cast;
using HR = std::chrono::high_resolution_clock;
using HRTimer = HR::time_point;
using std::chrono::microseconds;

void sanity_check_gpudata_CG(HoHGpu *gpuData, uint32_t unique_count) {
  for (uint32_t i = 0; i < unique_count; i++) {
    if (gpuData[i].unique_keys > 0) {
      int not_sentinel_keys = 0;
      for (uint32_t j = 0; j < getCapacity(rangeSize); j++) {
        if (gpuData[i].inner_hashtable[j].key != SENTINEL_KEY) {
          not_sentinel_keys++;
        }
      }

      if (not_sentinel_keys != gpuData[i].unique_keys) {
        cout << not_sentinel_keys << " " << gpuData[i].unique_keys << endl;
        for (uint32_t j = 0; j < getCapacity(rangeSize); j++) {
          if (gpuData[i].inner_hashtable[j].key != SENTINEL_KEY) {
            cout << gpuData[i].inner_hashtable[j].key << endl;
          }
        }
      }

      assert(not_sentinel_keys == gpuData[i].unique_keys);
    }
  }
}

__global__ void initialize_hash_CG(HoHGpu *hashTable, uint64_t gpuHTOuterSize,
                                   uint64_t inner_table_capacity) {
  uint64_t idx = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < gpuHTOuterSize) {
    // Initialize the inner hash table if needed
    for (uint32_t i = 0; i < inner_table_capacity; i++) {
      hashTable[idx].inner_hashtable[i].key = 0;
      hashTable[idx].inner_hashtable[i].value = 0;
    }
  }
}

/** Create the two-level heterohash structure using UVM. */
HoHGpu *createGPUHash_UVM_CG(uint64_t outer_slots_size,
                             uint64_t inner_ht_slots) {
  HoHGpu *gpu_outer_hash_table = nullptr;
  cudaCheckErrorMacro(cudaMallocManaged(&gpu_outer_hash_table,
                                        sizeof(HoHGpu) * outer_slots_size),
                      "[error] Allocation of outer hash table failed");

  uint64_t innerHTSize = inner_ht_slots * sizeof(KeyValue);

  for (uint64_t i = 0; i < outer_slots_size; i++) {
    cudaCheckErrorMacro(
        cudaMallocManaged(&gpu_outer_hash_table[i].inner_hashtable,
                          innerHTSize),
        "[error] Allocation for inner hash table failed");
  }
  return gpu_outer_hash_table;
}

__device__ uint32_t *insertgpu_inner_hashtable_CG(
    uint32_t key, KeyValue *hashtable, uint64_t inner_table_capacity,
    uint32_t rand_int, uint32_t range_size,
    uint32_t *unique_key_slot_of_outer_HT, uint64_t primeDHinner,
    const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint64_t pos = 0;
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
  pos = group.thread_rank();
#else
  if (primeDHinner > COOP_GROUP_SIZE)
    pos = COOP_GROUP_SIZE;
#endif
  uint64_t i = 0;
#if defined(HH)
  i = ((hashFuncIdentity(key) % inner_table_capacity) + group.thread_rank()) %
      inner_table_capacity;
#elif defined(SH)
  i = (hashFuncSH(key, rand_int) + group.thread_rank()) % inner_table_capacity;
#elif defined(MM)
  i = (hashFuncMurmur(key) + group.thread_rank()) % inner_table_capacity;
#else
  i = (((uint64_t)key * 11400714819323198485) + group.thread_rank()) %
      inner_table_capacity;
#endif
  uint64_t secondary_hash = primeDHinner;
#ifdef STATS
  __shared__ uint32_t c;
  c = 0;
#endif

  while (i < ~uint64_t(0)) {
    uint32_t key_p = hashtable[i].key;
    const bool hit = (key_p == key);
    const auto hitmask = group.ballot(hit);
    if (hitmask) {
      const auto leader = __ffs(hitmask) - 1;
      const auto leader_index = group.shfl(i, leader);
      // printf("The leader index in hitmask %d\n", leader_index);
      return (&hashtable[leader_index].value);
    }

    // Handle a collision in the inner hash table

    auto empty_mask = group.ballot(key_p == SENTINEL_KEY);
    bool success = false;
    bool duplicate = false;

    while (empty_mask) {
      const auto leader = __ffs(empty_mask) - 1;
      // if (group.thread_rank() == leader)
      //   printf("The hashed place is: %ld\n", i);

      if ((int)group.thread_rank() == leader) {
        const auto old = atomicCAS(&(hashtable[i].key), key_p, key);
        success = (old == key_p);
        duplicate = (old == key);
      }

      // Duplicate indicates a success
      if (group.any(duplicate)) {
        const auto leader_index = group.shfl(i, leader);
        // printf("In any sync: the leader index is: %d and key is: %d\n",
        //        leader_index, hashtable[leader_index].key);
        return (&hashtable[leader_index].value);
      }

      if (group.any(success)) {
        const auto leader_index = group.shfl(i, leader);
        // if (hashtable[leader_index].key == 134217729)
        //   printf("The leader index in success %d and key is: %d\n",
        //          leader_index, hashtable[leader_index].key);

        // FIXME: SB: Let us estimate the overhead of these atomics by disabling
        // them in a few runs.
        if ((int)group.thread_rank() == leader) {
          atomicAdd(unique_key_slot_of_outer_HT, 1);
        }
        return (&hashtable[leader_index].value);
      }

      // if (group.thread_rank() == leader)
      //   atomicAdd(&collision_list_outer[key / range_size], 1);

      // Zero out the first leader position (from MSB)
      empty_mask ^= (1UL << leader);
    }
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
    pos += COOP_GROUP_SIZE;
#else
    pos++;
#endif
#if defined(QUADRATIC_PROBING)
    i = ((i * i) + COOP_GROUP_SIZE) % inner_table_capacity;
#elif defined(LINEAR_PROBING)
    i = (i + COOP_GROUP_SIZE) % inner_table_capacity;
#else
    i = (i + secondary_hash) % inner_table_capacity;
#endif
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
    if (pos >= inner_table_capacity)
      i = ~uint64_t(0);
#else
    if (primeDHinner <= COOP_GROUP_SIZE &&
        pos >= (inner_table_capacity / primeDHinner) + 1) {
      // If the primeDH is less than or equal to 32 then we can gurantee that
      // the probing is done for all the slots.
      i = ~uint64_t(0);
    } else if (pos >= inner_table_capacity)
      // If the primeDH is more than 32 then we can gurantee that the probing
      // is done for all the slots only if it runs for the entire capacity.
      i = ~uint64_t(0);
#endif
  }
  return nullptr;
}

/** Find desired slot in the outer hash table based on the range. */
__device__ uint32_t *insertgpu_outer_hashtable_CG(
    uint32_t key, HoHGpu *hashtable, uint64_t inner_table_capacity,
    uint32_t range_detector_val, uint32_t rand_int, uint32_t range_size,
    uint64_t gpuHTOuterSize, uint64_t primeDH, uint64_t primeDHinner,
    const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint64_t pos = group.thread_rank();
  uint64_t outer_slot_index = 0;
  outer_slot_index = (range_detector_val) % gpuHTOuterSize;

  while (outer_slot_index < ~uint64_t(0)) {
    uint32_t range_detector_val_p = hashtable[outer_slot_index].range;
    const bool hit = (range_detector_val_p == range_detector_val);
    const auto hitmask = group.ballot(hit);
    if (hitmask) {
      const auto leader = __ffs(hitmask) - 1;
      const auto leader_index = group.shfl(outer_slot_index, leader);
      uint32_t *value_address = insertgpu_inner_hashtable_CG(
          key, hashtable[leader_index].inner_hashtable, inner_table_capacity,
          rand_int, range_size, &(hashtable[leader_index].unique_keys),
          primeDHinner, group);
      return value_address;
    }

    // Handle collision in the outer hash table
    auto empty_mask = group.ballot(range_detector_val_p == 0);
    bool success = false;
    bool duplicate = false;

    while (empty_mask) {
      const auto leader = __ffs(empty_mask) - 1;
      if (group.thread_rank() == leader) {
        const auto old = atomicCAS(&(hashtable[outer_slot_index].range),
                                   range_detector_val_p, range_detector_val);
        success = (old == range_detector_val_p);
        duplicate = (old == range_detector_val);
      }
      if (group.any(duplicate)) {

        const auto leader_index = group.shfl(outer_slot_index, leader);

        uint32_t *value_address = insertgpu_inner_hashtable_CG(
            key, hashtable[leader_index].inner_hashtable, inner_table_capacity,
            rand_int, range_size, &(hashtable[leader_index].unique_keys),
            primeDHinner, group);
        // if (group.thread_rank() == leader) {
        //   atomicAdd(&collision_list_outer[key / range_size], 1);
        // }
        return value_address;
      }
      if (group.any(success)) {
        const auto leader_index = group.shfl(outer_slot_index, leader);
        uint32_t *value_address = insertgpu_inner_hashtable_CG(
            key, hashtable[leader_index].inner_hashtable, inner_table_capacity,
            rand_int, range_size, &(hashtable[leader_index].unique_keys),
            primeDHinner, group);
        return value_address;
      }
      empty_mask ^= 1UL << leader;
    }
    pos += COOP_GROUP_SIZE;
    outer_slot_index = (outer_slot_index + COOP_GROUP_SIZE) % gpuHTOuterSize;
    if (pos >= gpuHTOuterSize)
      outer_slot_index = ~uint64_t(0);
  }
  return NULL;
}

/** One thread group inserts one key */
__device__ void
gpu_insert_key_CG(uint32_t key, uint32_t value, HoHGpu *hashtable,
                  uint64_t inner_table_capacity, uint32_t range_detector_val,
                  uint32_t rand_int, uint32_t range_size,
                  uint64_t outer_table_size, uint64_t primeDH,
                  uint64_t primeDHinner,
                  const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint32_t *value_addr = insertgpu_outer_hashtable_CG(
      key, hashtable, inner_table_capacity, range_detector_val, rand_int,
      range_size, outer_table_size, primeDH, primeDHinner, group);
  if (group.thread_rank() == 0 && value_addr != NULL) {
    *value_addr = value;
  }
}

/** One thread group will insert one element. */
__global__ void batch_insert_gpu_kernel_CG(
    HoHGpu *hashtable, KeyValue *kvs_array, uint64_t gpu_ins,
    uint64_t inner_table_capacity, uint32_t rand_int, uint32_t range_size,
    uint64_t outer_table_size, uint64_t primeDH, uint64_t primeDHinner) {
  size_t tid = (size_t)blockDim.x * blockIdx.x + threadIdx.x;
  size_t gid = tid / COOP_GROUP_SIZE;
  const auto group =
      cg::tiled_partition<COOP_GROUP_SIZE>(cg::this_thread_block());

  if (gid < gpu_ins) {
    gpu_insert_key_CG(
        kvs_array[gid].key, kvs_array[gid].value, hashtable,
        inner_table_capacity, (uint32_t)((kvs_array[gid].key / range_size) + 1),
        rand_int, range_size, outer_table_size, primeDH, primeDHinner, group);
  }
}

// Called by the driver
float batch_insert_gpu_unique_count_CG(HoHGpu *hashtable, KeyValue *uvm_kvpairs,
                                       uint64_t num_ins,
                                       uint64_t outer_table_size,
                                       uint64_t inner_table_size,
                                       uint32_t range_size) {
  uint64_t num_blocks = SDIV((num_ins * COOP_GROUP_SIZE), BlockSize);
  uint32_t rand_int = 0;

#if defined(SH)
  std::mt19937 rng(0);
  rand_int = rng() % PRIME_DIVISOR;
#endif

  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  cudaEventRecord(start, 0);
  batch_insert_gpu_kernel_CG<<<num_blocks, BlockSize>>>(
      hashtable, uvm_kvpairs, num_ins, inner_table_size, rand_int, range_size,
      outer_table_size, smallerPrimeGPU, smallerPrimeInner);

  cudaEventRecord(stop, 0);
  cudaEventSynchronize(stop);
  cudaCheckErrorMacro(cudaGetLastError(), "Insert kernel failure");
  float elapsedTime = 0.0f;
  cudaEventElapsedTime(&elapsedTime, start, stop);

#if defined(GPU_DEBUG)
  printf("HASHTABLE: GPU-batch insertion successfull\n");
  printf("Deallocation of memory successful\n");
#endif
  return elapsedTime;
}

__device__ bool
deletegpuimpl_key_CG(uint32_t key, KeyValue *innerHashtable,
                     uint64_t inner_table_capacity, uint32_t rand_int,
                     uint32_t *unique_key_slot_of_outer_HT,
                     uint64_t primeDHinner,
                     const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint64_t pos = group.thread_rank();
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
  pos = group.thread_rank();
#else
  if (primeDHinner > COOP_GROUP_SIZE)
    pos = group.thread_rank();
#endif
  uint64_t i = 0;
#if defined(HH)
  i = (((hashFuncIdentity(key) % inner_table_capacity) + group.thread_rank()) %
       inner_table_capacity);
  // printf("The value of i in HH is %ld\n", i);
#elif defined(SH)
  i = (hashFuncSH(key, rand_int) + group.thread_rank()) % inner_table_capacity;
#elif defined(MM)
  i = (hashFuncMurmur(key) + group.thread_rank()) % inner_table_capacity;
#else
  i = (((uint64_t)key * 11400714819323198485) + group.thread_rank()) %
      inner_table_capacity;
#endif
  uint64_t secondary_hash = primeDHinner;

  while (i < ~uint32_t(0)) {
    uint32_t key_p = innerHashtable[i].key;
    const bool hit = (key_p == key);
    // printf("Value of hit is %d\n", hit);
    const auto hitmask = group.ballot(hit);
    if (hitmask) {
      const auto leader = __ffs(hitmask) - 1;
      // const auto leader_index = group.shfl(i, leader);
      if ((int)group.thread_rank() == leader) {
        innerHashtable[i].key = TOMBSTONE_KEY;
        innerHashtable[i].value = TOMBSTONE_VALUE;

        // atomicSub(unique_key_slot_of_outer_HT, 1);
        (*unique_key_slot_of_outer_HT)--;
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
    i = ((i * i) + COOP_GROUP_SIZE) % inner_table_capacity;
#elif defined(LINEAR_PROBING)
    i = (i + COOP_GROUP_SIZE) % inner_table_capacity;
#else
    i = (i + secondary_hash) % inner_table_capacity;
#endif
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
    if (pos >= inner_table_capacity)
      i = ~uint64_t(0);
#else
    if (primeDHinner <= COOP_GROUP_SIZE &&
        pos >= (inner_table_capacity / primeDHinner) + 1) {
      // If the primeDH is less than or equal to 32 then we can gurantee that
      // the probing is done for all the slots.
      i = ~uint32_t(0);
    } else if (pos >= inner_table_capacity)
      // If the primeDH is more than 32 then we can gurantee that the probing
      // is done for all the slots only if it runs for the entire capacity.
      i = ~uint32_t(0);
#endif
  }
  return false;
}

__device__ bool
deletegpuimpl_CG(uint32_t key, HoHGpu *hashtable, uint64_t inner_table_capacity,
                 uint32_t range_detector_val, uint32_t rand_int,
                 uint32_t range_size, uint64_t gpuHTOuterSize, uint64_t primeDH,
                 uint64_t primeDHinner,
                 const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint64_t pos = group.thread_rank();
  uint64_t outer_slot_index = 0;
  outer_slot_index = (range_detector_val) % gpuHTOuterSize;
  while (outer_slot_index < ~uint32_t(0)) {
    uint32_t range_detector_val_p = hashtable[outer_slot_index].range;
    const bool hit = (range_detector_val_p == range_detector_val);
    const auto hitmask = group.ballot(hit);
    if (hitmask) {
      const auto leader = __ffs(hitmask) - 1;
      const auto leader_index = group.shfl(outer_slot_index, leader);
      bool status = deletegpuimpl_key_CG(
          key, hashtable[leader_index].inner_hashtable, inner_table_capacity,
          rand_int, &(hashtable[leader_index].unique_keys), primeDHinner,
          group);
      if ((int)group.thread_rank() == leader &&
          hashtable[leader_index].unique_keys == 0) {
        hashtable[leader_index].range = 0;
      }
      return status;
    }
    if (group.any(range_detector_val_p == 0)) {
      return false;
    }
#ifdef STATS
    if (group.thread_rank() == leader)
      atomicInc(&c, maxCollisions);
#endif
    pos += COOP_GROUP_SIZE;
    outer_slot_index = (outer_slot_index + COOP_GROUP_SIZE) % gpuHTOuterSize;
    if (pos >= gpuHTOuterSize)
      outer_slot_index = ~uint32_t(0);
  }
  return false;
}

__global__ void
batch_delete_gpu_kernel_CG(HoHGpu *hashtable, uint32_t *del_keys,
                           uint64_t gpu_del, uint64_t inner_table_capacity,
                           uint32_t rand_int, uint32_t range_size,
                           uint64_t outer_table_size, uint64_t primeDH,
                           uint64_t primeDHinner, bool *delete_status) {
  size_t tid = (size_t)blockDim.x * blockIdx.x + threadIdx.x;
  size_t gid = tid / COOP_GROUP_SIZE;
  const auto group =
      cg::tiled_partition<COOP_GROUP_SIZE>(cg::this_thread_block());
  if (gid < gpu_del) {
    bool del = deletegpuimpl_CG(del_keys[gid], hashtable, inner_table_capacity,
                                (uint32_t)((del_keys[gid] / range_size) + 1),
                                rand_int, range_size, outer_table_size, primeDH,
                                primeDHinner, group);
    if (group.thread_rank() == 0) {
      if (del == true)
        delete_status[gid] = del;
    }
  }
}

// Called by the driver
float batch_delete_gpu_unique_count_CG(HoHGpu *Hashtable,
                                       uint32_t *uvm_del_keys, uint64_t num_del,
                                       uint64_t outer_table_size,
                                       uint64_t inner_table_capacity,
                                       uint32_t range_size,
                                       bool *delete_status) {
  uint64_t num_blocks = SDIV((num_del * COOP_GROUP_SIZE), BlockSize);
  uint32_t rand_int = 0;

#if defined(SH)
  std::mt19937 rng(0);
  rand_int = rng() % PRIME_DIVISOR;
#endif

  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  cudaEventRecord(start, 0);
  batch_delete_gpu_kernel_CG<<<(uint32_t)num_blocks, BlockSize>>>(
      Hashtable, uvm_del_keys, num_del, inner_table_capacity, rand_int,
      range_size, outer_table_size, smallerPrimeGPU, smallerPrimeInner,
      delete_status);

  cudaEventRecord(stop, 0);
  cudaEventSynchronize(stop);
  cudaCheckErrorMacro(cudaGetLastError(), "Delete kernel failure");
  float elapsedTime = 0.0f;
  cudaEventElapsedTime(&elapsedTime, start, stop);

#if defined(GPU_DEBUG)
  printf("HASHTABLE: GPU-batch insertion successfull\n");
  printf("Deallocation of memory successful\n");
#endif
  return elapsedTime;
}

__device__ uint32_t searchgpuimpl_key_CG(
    uint32_t key, KeyValue *innerHashtable, uint64_t inner_table_capacity,
    uint32_t rand_int, uint64_t primeDHinner,
    const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint64_t pos = group.thread_rank();
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
  pos = group.thread_rank();
#else
  if (primeDHinner > COOP_GROUP_SIZE)
    pos = COOP_GROUP_SIZE;
#endif
  uint64_t i = 0;
#if defined(HH)
  i = (((hashFuncIdentity(key) % inner_table_capacity) + group.thread_rank()) %
       inner_table_capacity);
#elif defined(SH)
  i = (hashFuncSH(key, rand_int) + group.thread_rank()) % inner_table_capacity;
#elif defined(MM)
  i = (hashFuncMurmur(key) + group.thread_rank()) % inner_table_capacity;
#else
  i = (((uint64_t)key * 11400714819323198485) + group.thread_rank()) %
      inner_table_capacity;
#endif
  uint64_t secondary_hash = primeDHinner;

  while (i < ~uint64_t(0)) {
    uint32_t key_p = innerHashtable[i].key;
    const bool hit = (key_p == key);
    // printf("Value of hit is %d\n", hit);
    const auto hitmask = group.ballot(hit);
    if (hitmask) {
      const auto leader = __ffs(hitmask) - 1;
      const auto leader_index = group.shfl(i, leader);
      // printf("The leader index in hitmask %d\n", leader_index);
      return (innerHashtable[leader_index].value);
    }
    if (group.any((key_p == SENTINEL_KEY))) {
      return 0;
    }
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
    pos += COOP_GROUP_SIZE;
#else
    pos++;
#endif
#if defined(QUADRATIC_PROBING)
    i = ((i * i) + COOP_GROUP_SIZE) % inner_table_capacity;
#elif defined(LINEAR_PROBING)
    i = (i + COOP_GROUP_SIZE) % inner_table_capacity;
#else
    i = (i + secondary_hash) % inner_table_capacity;
#endif
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
    if (pos >= inner_table_capacity)
      i = ~uint64_t(0);
#else
    if (primeDHinner <= COOP_GROUP_SIZE &&
        pos >= (inner_table_capacity / primeDHinner) + 1) {
      // If the primeDH is less than or equal to 32 then we can gurantee that
      // the probing is done for all the slots.
      i = ~uint64_t(0);
    } else if (pos >= inner_table_capacity)
      // If the primeDH is more than 32 then we can gurantee that the probing
      // is done for all the slots only if it runs for the entire capacity.
      i = ~uint64_t(0);
#endif
  }
  return 0;
}

__device__ uint32_t searchgpuimpl_CG(
    uint32_t key, HoHGpu *hashtable, uint64_t inner_table_capacity,
    uint32_t range_detector_val, uint32_t rand_int, uint32_t range_size,
    uint64_t gpuHTOuterSize, uint64_t primeDH, uint64_t primeDHinner,
    const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint64_t pos = group.thread_rank();
  uint64_t outer_slot_index = 0;
  outer_slot_index =
      (range_detector_val + group.thread_rank()) % gpuHTOuterSize;
  while (outer_slot_index < ~uint64_t(0)) {
    uint32_t range_detector_val_p = hashtable[outer_slot_index].range;
    const bool hit = (range_detector_val_p == range_detector_val);
    const auto hitmask = group.ballot(hit);
    if (hitmask) {
      const auto leader = __ffs(hitmask) - 1;
      const auto leader_index = group.shfl(outer_slot_index, leader);
      uint32_t value = searchgpuimpl_key_CG(
          key, hashtable[leader_index].inner_hashtable, inner_table_capacity,
          rand_int, primeDHinner, group);
      return value;
    }
    if (hashtable[outer_slot_index].range == 0) {
      return 0;
    }
#ifdef STATS
    if (group.thread_rank() == leader)
      atomicInc(&c, maxCollisions);
#endif
    pos += COOP_GROUP_SIZE;
    outer_slot_index = (outer_slot_index + COOP_GROUP_SIZE) % gpuHTOuterSize;
    if (pos >= gpuHTOuterSize)
      outer_slot_index = ~uint64_t(0);
  }
  return 0;
}

__global__ void
batch_search_gpu_kernel_CG(HoHGpu *hashtable, uint32_t *search_keys,
                           uint64_t gpu_search, uint64_t inner_table_capacity,
                           uint32_t rand_int, uint32_t range_size,
                           uint64_t outer_table_size, uint64_t primeDH,
                           uint64_t primeDHinner, uint32_t *search_values) {
  size_t tid = (size_t)blockDim.x * blockIdx.x + threadIdx.x;
  size_t gid = tid / COOP_GROUP_SIZE;
  const auto group =
      cg::tiled_partition<COOP_GROUP_SIZE>(cg::this_thread_block());

  if (gid < gpu_search) {
    // if (group.thread_rank() == 0)
    //   printf("Wid are: %d\n", wid);
    uint32_t value = searchgpuimpl_CG(
        search_keys[gid], hashtable, inner_table_capacity,
        (uint32_t)((search_keys[gid] / range_size) + 1), rand_int, range_size,
        outer_table_size, primeDH, primeDHinner, group);
    if (group.thread_rank() == 0) {
      if (value != 0)
        search_values[gid] = value;
    }
  }
}

// Called by the driver
float batch_search_gpu_unique_count_CG(HoHGpu *Hashtable, uint32_t *search_keys,
                                       uint64_t num_search,
                                       uint64_t outer_table_size,
                                       uint64_t inner_table_capacity,
                                       uint32_t range_size,
                                       uint32_t *search_values) {
  uint64_t num_blocks = SDIV((num_search * COOP_GROUP_SIZE), BlockSize);
  uint32_t rand_int = 0;
#if defined(SH)
  std::mt19937 rng(0);
  rand_int = rng() % PRIME_DIVISOR;
#endif

  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  cudaEventRecord(start, 0);
  batch_search_gpu_kernel_CG<<<(uint32_t)num_blocks, BlockSize>>>(
      Hashtable, search_keys, num_search, inner_table_capacity, rand_int,
      range_size, outer_table_size, smallerPrimeGPU, smallerPrimeInner,
      search_values);

  cudaEventRecord(stop, 0);
  cudaEventSynchronize(stop);
  cudaCheckErrorMacro(cudaGetLastError(), "Search kernel failure");

  float elapsedTime = 0.0f;
  cudaEventElapsedTime(&elapsedTime, start, stop);

#if defined(GPU_DEBUG)
  printf("HASHTABLE: GPU-batch insertion successfull\n");
  printf("Deallocation of memory successful\n");
#endif
  return elapsedTime;
}

__global__ void print_kernel_CG(HoHGpu *hashTable, uint64_t outer_table_size,
                                uint32_t inner_table_capacity) {
  size_t tid = (size_t)blockDim.x * blockIdx.x + threadIdx.x;
  uint64_t count = 0;
  if (tid == 0) {
    for (uint64_t i = 0; i < outer_table_size; i++) {
      // if (hashTable[i].unique_keys != 0) {
      // count += hashTable[i].unique_keys;
      // printf("Outer Table range value: %d\n", hashTable[i].range);
      for (uint32_t j = 0; j < inner_table_capacity; j++) {
        // if (hashTable[i].inner_hashtable[j].key != SENTINEL_KEY &&
        //     hashTable[i].inner_hashtable[j].key != TOMBSTONE_KEY)
        // printf("Key: %d, Value: %d\n", hashTable[i].inner_hashtable[j].key,
        //        hashTable[i].inner_hashtable[j].value);
        count++;
      }
      // }
    }
    printf("Total unique keys in hashtable: %lu\n", count);
  }
}

void printGpuHashTable_CG(HoHGpu *hashTable, uint64_t outer_table_size,
                          uint32_t inner_table_capacity) {
  printf("Start printing the GPU hash table\n");
  print_kernel_CG<<<1, BlockSize>>>(hashTable, outer_table_size,
                                    inner_table_capacity);
  cudaDeviceSynchronize();
  printf("Printing the GPU hash table completed\n");
}

void KeyCheckGPUHoH_CG(HoHGpu *gpuHashTable, uint64_t gpu_outer_slot_size,
                       KeyValue *gpuInsertionList, uint64_t totalInsertion) {
  std::vector<KeyValue> inserted_entries;
  inserted_entries.reserve(totalInsertion);

  // Collect all (key, value) pairs from the insertion list
  for (uint64_t i = 0; i < totalInsertion; i++) {
    inserted_entries.push_back(gpuInsertionList[i]);
  }

  // Optional: Remove duplicates if needed
  std::sort(inserted_entries.begin(), inserted_entries.end(), compareByKey);
  auto last = std::unique(inserted_entries.begin(), inserted_entries.end(),
                          [](const KeyValue &a, const KeyValue &b) {
                            return a.key == b.key && a.value == b.value;
                          });
  inserted_entries.erase(last, inserted_entries.end());

  // Collect all valid (key, value) pairs from the hash table
  std::vector<KeyValue> ht_entries;
  for (uint32_t i = 0; i < gpu_outer_slot_size; i++) {
    if (gpuHashTable[i].range != UINT32_MAX) {
      for (uint32_t j = 0; j < getCapacity(rangeSize); j++) {
        const auto &entry = gpuHashTable[i].inner_hashtable[j];
        if (entry.key != SENTINEL_KEY && entry.value != SENTINEL_VALUE) {
          ht_entries.push_back(entry);
        }
      }
    }
  }

  std::cout << "Total inserts: " << inserted_entries.size()
            << " | Keys inserted in hash table: " << ht_entries.size() << "\n";

  // Sort both vectors for comparison
  std::sort(ht_entries.begin(), ht_entries.end(), compareByKey);

  // Compare sizes
  if (ht_entries.size() != inserted_entries.size()) {
    std::cout << "Mismatch in number of valid entries: hash table "
              << ht_entries.size() << " vs inserted " << inserted_entries.size()
              << "\n";
  }

  // Compare element-wise
  uint64_t total_mismatches = 0;
  uint64_t compare_limit = std::min(ht_entries.size(), inserted_entries.size());

  for (uint64_t i = 0; i < compare_limit; i++) {
    if (ht_entries[i].key != inserted_entries[i].key ||
        ht_entries[i].value != inserted_entries[i].value) {
      total_mismatches++;
      // std::cout << "Mismatch at index " << i << ": HT(" << ht_entries[i].key
      //           << "," << ht_entries[i].value << ") vs "
      //           << "Ins(" << inserted_entries[i].key << ","
      //           << inserted_entries[i].value << ")\n";
    }
  }

  std::cout << "Total mismatches: " << total_mismatches << "\n";
}

void KeyCheckGPUHoH_Delete_CG(HoHGpu *gpuHashTable,
                              uint64_t gpu_outer_slot_size,
                              uint32_t *gpuDeletionList,
                              uint64_t totalDeletions) {
  std::unordered_set<uint32_t> deleted_keys;

  // Collect all keys from the deletion list
  for (uint64_t i = 0; i < totalDeletions; i++) {
    deleted_keys.insert(gpuDeletionList[i]);
  }

  std::cout << "Expected deletions (unique keys): " << deleted_keys.size()
            << "\n";

  uint64_t total_failed_deletes = 0;

  // For each outer slot in the hash table
  for (uint32_t i = 0; i < gpu_outer_slot_size; i++) {
    if (gpuHashTable[i].range != UINT32_MAX) {
      for (uint32_t j = 0; j < getCapacity(rangeSize); j++) {
        const auto &entry = gpuHashTable[i].inner_hashtable[j];

        // If entry is valid (i.e., not empty or tombstone)
        if (entry.key != SENTINEL_KEY && entry.key != TOMBSTONE_KEY) {
          // If the key is in the deleted list, it's a failed deletion
          if (deleted_keys.count(entry.key)) {
            std::cout << "Failed deletion: Key " << entry.key
                      << " still exists with value " << entry.value << "\n";
            total_failed_deletes++;
          }
        }
      }
    }
  }

  std::cout << "Total failed deletions: " << total_failed_deletes << "\n";
}
