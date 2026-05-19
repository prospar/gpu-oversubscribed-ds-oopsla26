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
// #include "gpu_part_batch_HoH.cuh"

namespace cg = cooperative_groups;

using std::cout;
using std::endl;
using std::string;
using std::vector;

using std::chrono::duration_cast;
using HR = std::chrono::high_resolution_clock;
using HRTimer = HR::time_point;
using std::chrono::microseconds;

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
    uint32_t range_size, uint32_t *unique_key_slot_of_outer_HT,
    uint64_t primeDHinner,
    const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint64_t pos = 0;
#if defined(LINEAR_PROBING) || defined(QUADRATIC_PROBING)
  pos = group.thread_rank();
#else
  if (primeDHinner > COOP_GROUP_SIZE)
    pos = COOP_GROUP_SIZE;
#endif
  uint64_t i = 0;
  i = (((uint64_t)key * 11400714819323198485) + group.thread_rank()) %
      inner_table_capacity;
  uint64_t secondary_hash = primeDHinner;

  while (i < ~uint64_t(0)) {
    uint32_t key_p = hashtable[i].key;
    const bool hit = (key_p == key);
    const auto hitmask = group.ballot(hit);
    if (hitmask) {
      const auto leader = __ffs(hitmask) - 1;
      const auto leader_index = group.shfl(i, leader);
      return (&hashtable[leader_index].value);
    }

    auto empty_mask = group.ballot(key_p == SENTINEL_KEY);
    bool success = false;
    bool duplicate = false;

    while (empty_mask) {
      const auto leader = __ffs(empty_mask) - 1;
      if ((int)group.thread_rank() == leader) {
        const auto old = atomicCAS(&(hashtable[i].key), key_p, key);
        success = (old == key_p);
        duplicate = (old == key);
      }

      // Duplicate indicates a success
      if (group.any(duplicate)) {
        const auto leader_index = group.shfl(i, leader);
        return (&hashtable[leader_index].value);
      }

      if (group.any(success)) {
        const auto leader_index = group.shfl(i, leader);
        if ((int)group.thread_rank() == leader) {
          atomicAdd(unique_key_slot_of_outer_HT, 1);
        }
        return (&hashtable[leader_index].value);
      }
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
  return NULL;
}

/** Find desired slot in the outer hash table based on the range. */
__device__ uint32_t *insertgpu_outer_hashtable_CG(
    uint32_t key, HoHGpu *hashtable, uint64_t inner_table_capacity,
    uint32_t range_detector_val, uint32_t range_size, uint64_t gpuHTOuterSize,
    uint64_t primeDH, uint64_t primeDHinner,
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
      uint32_t *value = insertgpu_inner_hashtable_CG(
          key, hashtable[leader_index].inner_hashtable, inner_table_capacity,
          range_size, &(hashtable[leader_index].unique_keys), primeDHinner,
          group);
      return value;
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

        uint32_t *value = insertgpu_inner_hashtable_CG(
            key, hashtable[leader_index].inner_hashtable, inner_table_capacity,
            range_size, &(hashtable[leader_index].unique_keys), primeDHinner,
            group);
        return value;
      }
      if (group.any(success)) {
        const auto leader_index = group.shfl(outer_slot_index, leader);
        uint32_t *value = insertgpu_inner_hashtable_CG(
            key, hashtable[leader_index].inner_hashtable, inner_table_capacity,
            range_size, &(hashtable[leader_index].unique_keys), primeDHinner,
            group);
        return value;
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

__device__ void
gpu_insert_key_CG(uint32_t key, uint32_t value, HoHGpu *hashtable,
                  uint64_t inner_table_capacity, uint32_t range_detector_val,
                  uint32_t range_size, uint64_t outer_table_size,
                  uint64_t primeDH, uint64_t primeDHinner,
                  const cg::thread_block_tile<COOP_GROUP_SIZE> &group) {
  uint32_t *value_addr = insertgpu_outer_hashtable_CG(
      key, hashtable, inner_table_capacity, range_detector_val, range_size,
      outer_table_size, primeDH, primeDHinner, group);
  if (group.thread_rank() == 0 && value_addr != NULL) {
    atomicAdd(value_addr, 1);
    // (*value_addr)++;
  }
}

/** One thread group will insert one element. */
__global__ void
batch_insert_gpu_kernel_CG(HoHGpu *hashtable, KeyValue *kvpairs,
                           uint64_t gpu_ins, uint64_t inner_table_capacity,
                           uint32_t range_size, uint64_t outer_table_size,
                           uint64_t primeDH, uint64_t primeDHinner) {
  size_t tid = (size_t)blockDim.x * blockIdx.x + threadIdx.x;
  size_t gid = tid / COOP_GROUP_SIZE;
  const auto group =
      cg::tiled_partition<COOP_GROUP_SIZE>(cg::this_thread_block());

  if (gid < gpu_ins) {
    gpu_insert_key_CG(
        kvpairs[gid].key, kvpairs[gid].value, hashtable, inner_table_capacity,
        (uint32_t)((kvpairs[gid].key / range_size) + 1), range_size,
        outer_table_size, primeDH, primeDHinner, group);
  }
}

// Called by the driver
float batch_insert_gpu_unique_count_CG(HoHGpu *hashtable, KeyValue *kvpairs,
                                       uint64_t num_ins,
                                       uint64_t outer_table_size,
                                       uint64_t inner_table_size,
                                       uint32_t range_size) {
  uint64_t num_blocks = SDIV((num_ins * COOP_GROUP_SIZE), BlockSize);

  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  cudaEventRecord(start, 0);
  batch_insert_gpu_kernel_CG<<<num_blocks, BlockSize>>>(
      hashtable, kvpairs, num_ins, inner_table_size, range_size,
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

__device__ uint32_t searchgpuimpl_key_CG(
    uint32_t key, KeyValue *innerHashtable, uint64_t inner_table_capacity,
    uint32_t rand_int, uint32_t *unique_count, uint64_t primeDHinner,
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
#ifdef STATS
      if (group.thread_rank() == leader)
        printf("The collision count(from hit) is %d\n", c);
#endif
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
    uint32_t range_detector_val, uint32_t rand_int, uint32_t *unique_count,
    uint32_t range_size, uint64_t gpuHTOuterSize, uint64_t primeDH,
    uint64_t primeDHinner,
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
          rand_int, unique_count, primeDHinner, group);
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

__global__ void batch_search_gpu_kernel_CG(
    HoHGpu *hashtable, uint32_t *search_keys, uint64_t gpu_search,
    uint64_t inner_table_capacity, uint32_t rand_int, uint32_t *unique_count,
    uint32_t range_size, uint64_t outer_table_size, uint64_t primeDH,
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
        (uint32_t)((search_keys[gid] / range_size) + 1), rand_int, unique_count,
        range_size, outer_table_size, primeDH, primeDHinner, group);
    if (group.thread_rank() == 0) {
      if (value != 0)
        search_values[gid] = value;
    }
  }
}

// Called by the driver
float batch_search_gpu_unique_count_CG(
    HoHGpu *Hashtable, uint32_t *search_keys, uint64_t num_search,
    uint64_t outer_table_size, uint64_t inner_table_capacity,
    uint32_t range_size, uint32_t *search_values, uint32_t *unique_count) {
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
      unique_count, range_size, outer_table_size, smallerPrimeGPU,
      smallerPrimeInner, search_values);

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
