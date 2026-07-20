#include "functions.h"
#include "skiplist_stats.cuh"

#include <algorithm>
#include <assert.h>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <execution>
#include <memory>
#include <set>
#if defined(ENABLE_SORT)
#include <thrust/execution_policy.h>
#include <thrust/sort.h>
#endif

#if defined(FIXED_INDEX)
#include "skiplist_gfsl_fixed_index.cuh"
#elif defined(UNSORTED_IMPL)
#include "skiplist_gfsl_unsorted.cuh"
#elif defined(SEPARATE_POOL)
#include "skiplist_gfsl_separate_pool.cuh"
#else
#include "skiplist_gfsl.cuh"
#endif

using namespace std;

using HRClock = std::chrono::high_resolution_clock;
using DurationFloatMS = std::chrono::duration<float, std::milli>;

__global__ void batch_insert(uint64_t numWarps, uint64_t len, GFSL *skiplist,
                             KeyValue *keyValList, uint32_t *resList,
#if defined(BUSY_WAIT)
                             int *allowWarp, int keysPerWarp, int waitingWarps,
#endif
                             SkiplistStats *stats) {
  size_t tid = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
  size_t warpId = tid >> 5;

  // int ops_per_warp = (len + numWarps - 1) / numWarps ;
  // for(int i = warpId * ops_per_warp; i < (warpId + 1) * ops_per_warp; i++){
  //     if(i < len) resList[i] = skiplist->insert(keyList[i], valList[i]);
  // }

#if defined(BUSY_WAIT)
  for (uint64_t i = (keysPerWarp * warpId); i < len;
       i += (keysPerWarp * numWarps)) {
#else
  for (uint64_t i = warpId; i < len; i += numWarps) {
#endif
#if defined(BUSY_WAIT)
    int lane = tid & 31;
    int arrLockId = (warpId < waitingWarps) ? warpId : (waitingWarps - 1);
    if (lane == 0)
      while (atomicAdd(&allowWarp[arrLockId], 0) == 0)
        ;
    //__syncwarp();
    int j = 0;
    for (; j < keysPerWarp; j++) {
      if (i + j < len) {
        resList[i + j] = skiplist->insert(keyValList[i + j].key,
                                          keyValList[i + j].value, stats);
      }
    }
    if (lane == 0) {
      if (warpId + 1 < waitingWarps) {
        atomicExch(&allowWarp[arrLockId + 1], 1);
        // printf("Warp %d exiting If\n", warpId);
      } else {
        // printf("Warp %d exiting Else\n", warpId);
        atomicExch(&allowWarp[0], 1);
      }
    }
    //__syncwarp();
#else
    resList[i] =
        skiplist->insert(keyValList[i].key, keyValList[i].value, stats);
#endif
  }
}

__global__ void batch_delete(int numWarps, uint64_t len, GFSL *skiplist,
                             uint32_t *keyList, uint32_t *resList,
#if defined(BUSY_WAIT)
                             int *allowWarp, int keysPerWarp, int waitingWarps,
#endif
                             SkiplistStats *stats) {
  size_t tid = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
  uint64_t warpId = tid >> 5;
#if defined(BUSY_WAIT)
  for (uint64_t i = (keysPerWarp * warpId); i < len;
       i += (keysPerWarp * numWarps)) {
#else
  for (uint64_t i = warpId; i < len; i += numWarps) {
#endif
#if defined(BUSY_WAIT)
    int lane = tid & 31;
    int arrLockId = (warpId < waitingWarps) ? warpId : (waitingWarps - 1);
    if (lane == 0)
      while (atomicAdd(&allowWarp[arrLockId], 0) == 0)
        ;
    //__syncwarp();
    int j = 0;
    for (; j < keysPerWarp; j++) {
      if (i + j < len) {
        resList[i + j] = skiplist->erase(keyList[i + j], stats);
      }
    }
    if (lane == 0) {
      if (warpId + 1 < waitingWarps) {
        atomicExch(&allowWarp[arrLockId + 1], 1);
        // printf("Warp %d exiting If\n", warpId);
      } else {
        // printf("Warp %d exiting Else\n", warpId);
        atomicExch(&allowWarp[0], 1);
      }
      // atomicExch(&allowWarp[arrLockId],0);
    }
    //__syncwarp();
#else
    resList[i] = skiplist->erase(keyList[i], stats);
#endif
  }
}

__global__ void batch_contains(uint64_t numWarps, uint64_t len, GFSL *skiplist,
                               uint32_t *keyList, uint32_t *resList,
#if defined(BUSY_WAIT_SEARCH)
                               int keysPerWarp,
#endif
                               SkiplistStats *stats) {
  size_t tid = (size_t)(threadIdx.x + blockIdx.x * blockDim.x);
  uint64_t warpId = tid >> 5;
#if defined(BUSY_WAIT_SEARCH)
  for (uint64_t i = (keysPerWarp * warpId); i < len;
       i += (keysPerWarp * numWarps)) {
#else
  for (uint64_t i = warpId; i < len; i += numWarps) {
#endif
#if defined(BUSY_WAIT_SEARCH)
    // int lane = tid & 31;
    // if (lane == 0)
    //     while (atomicAdd(&allowWarp[warpId],0) == 0);
    // __syncwarp();
    int j = 0;
    for (; j < keysPerWarp; j++) {
      if (i + j < len) {
        resList[i + j] = skiplist->contains(keyList[i + j], stats).kv.value;
      }
    }

#else
    resList[i] = skiplist->contains(keyList[i], stats).kv.value;
#endif
  }
}

__global__ void delete_kernel_correctness_check(uint64_t numWarps, uint64_t len,
                                                GFSL *skiplist,
                                                uint32_t *keyList,
                                                uint32_t *resList) {
  size_t tid = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
  uint64_t warpId = tid >> 5;

  for (uint64_t i = warpId; i < len; i += numWarps) {
    // if (i < len) // redundant check as i is already less than len
    resList[i] = skiplist->deleteCorrectness(keyList[i]);
  }
}

__global__ void batch_predecessor(uint64_t numWarps, uint64_t len,
                                  GFSL *skiplist, uint32_t *keyList,
                                  uint32_t *resList,
#if defined(BUSY_WAIT_SEARCH)
                                  int keysPerWarp,
#endif
                                  SkiplistStats *stats) {
  size_t tid = (size_t)(threadIdx.x + blockIdx.x * blockDim.x);
  uint64_t warpId = tid >> 5;
#if defined(BUSY_WAIT_SEARCH)
  for (uint64_t i = (keysPerWarp * warpId); i < len;
       i += (keysPerWarp * numWarps)) {
#else
  for (uint64_t i = warpId; i < len; i += numWarps) {
#endif
#if defined(BUSY_WAIT_SEARCH)
    // int lane = tid & 31;
    // if (lane == 0)
    //     while (atomicAdd(&allowWarp[warpId],0) == 0);
    // __syncwarp();
    int j = 0;
    for (; j < keysPerWarp; j++) {
      if (i + j < len) {
        resList[i + j] =
            skiplist->getPredecessorKey(keyList[i + j], stats).kv.key;
      }
    }

#else
    resList[i] = skiplist->getPredecessorKey(keyList[i], stats).kv.key;
    // if ((tid & 31) == 0) {
    //   printf("Key: %u Predecessor: %u\n", keyList[i], resList[i]);
    // }
#endif
  }
}

__global__ void findLastKey(GFSL *skiplist, uint32_t *resList) {
  resList[0] = skiplist->findLast();
}

__global__ void findFirstKey(GFSL *skiplist, uint32_t *resList) {
  resList[0] = skiplist->findFirst();
}
int main(int argc, char *argv[]) {

  // parse_cmd(argc, argv);
  for (uint32_t i = 1; i < argc; i++) {
    if (parse_args(argv[i])) {
      std::cout << argv[i] << "\n";
      cerr << "[ERROR] Argument error, terminating run.\n";
      exit(EXIT_FAILURE);
    }
  }
  cout << "starting benchmark:\n";

  size_t free, tot;
  cudaCheckErrorMacro(cudaMemGetInfo(&free, &tot),
                      "Error in getting memory info");
  std::vector<DeviceMemReservation> reservations;
  if (OVERSUB_RATIO) {
    reservations = query_and_reserve();
    cout << "Oversubscription enabled with ratio: " << OVERSUB_RATIO << "\n";
    printf("\n%-8s  %-8s  %-16s  %-16s\n", "Device", "Total", "Reserved",
           "Available");
    printf("%-8s  %-8s  %-16s  %-16s\n", "------", "-----", "--------",
           "--------");
    for (const auto &r : reservations) {
      printf("%-8d  %5.2f GiB  %12.2f GiB  %12.2f GiB\n", r.device_id,
             static_cast<double>(r.total_bytes) / GiB,
             static_cast<double>(r.reserved) / GiB,
             static_cast<double>(r.total_bytes - r.reserved) / GiB);
    }
  }

  uint64_t ADD = NUM_ADD_OPS;
  assert(ADD > 0);
  uint64_t REM = NUM_REM_OPS;
  uint64_t FIND = NUM_OPS - (ADD + REM);
  uint32_t *keys_del = nullptr;    // new uint32_t[REM];
  uint32_t *keys_lookup = nullptr; // new uint32_t[FIND];
  // uint32_t *keys_insert = nullptr;        // new uint32_t[ADD];
  // uint32_t *values_insert = nullptr;      // new uint32_t[ADD];
  KeyValue *keys_values_insert = nullptr; // new uint32_t[ADD];
  power_of_two = 1;
  // uint32_t *keyCheckArr = new uint32_t[ADD];
  cout << "ADD: " << ADD << " SEARCH: " << FIND << " DELETE: " << REM << "\n";
  if (REM)
    cudaCheckErrorMacro(
        cudaMallocManaged((void **)&keys_del, sizeof(uint32_t) * REM),
        "Mem allocation failed for keys_del");
  if (FIND)
    cudaCheckErrorMacro(
        cudaMallocManaged((void **)&keys_lookup, sizeof(uint32_t) * FIND),
        "Mem allocation failed for keys_lookup");
  // cudaCheckErrorMacro(
  //     cudaMallocManaged((void **)&keys_insert, sizeof(uint32_t) * ADD),
  //     "Mem allocation failed for keys_insert");
  // cudaCheckErrorMacro(
  //     cudaMallocManaged((void **)&values_insert, sizeof(uint32_t) * ADD),
  //     "Mem allocation failed for values_insert");
  cudaCheckErrorMacro(
      cudaMallocManaged((void **)&keys_values_insert, sizeof(KeyValue) * ADD),
      "Mem allocation failed for keys_values_insert");
  if (!checkTraceFilesSL(addTrace, delTrace, findTrace, keys_values_insert,
                         keys_del, keys_lookup)) {
    cerr << "[Error] Unable to read trace\n";
  }

// Copy inserted key to temp arr for verification
#if defined(KEY_CHECK)
  for (uint64_t i = 0; i < ADD; i++) {
    // keyCheckArr[i] = keys_values_insert[i].key;
  }
#endif

  // vector to track timing of each run
  std::vector<iterationTime> iterTimes;
  iterTimes.reserve(runs);
#if defined(ENABLE_SORT)
  static simple_cached_allocator<KeyValue> alloc;
#endif

  // iterations per launch
  uint32_t iterPerLaunch = 0;
  for (; iterPerLaunch < runs; iterPerLaunch++) {
    // Cost across per-batch kernel launches
    float total_time = 0.0f;
    float total_insert_time = 0.0f;
    float total_delete_time = 0.0f;
    float total_search_time = 0.0f;
    float total_predecessor_time = 0.0f;
    float total_batch_time = 0.0f;
    float total_sort_time = 0.0f;
    float total_sort_time_insert = 0.0f;
    float total_sort_time_delete = 0.0f;
    float total_sort_time_search = 0.0f;
    float total_sort_time_predecessor = 0.0f;

#if defined(BATCH_IMPL)
    // Cumulative cost of creating multiple batches
    float total_batch_time_insert = 0.0f;
    float total_batch_time_delete = 0.0f;
    float total_batch_time_search = 0.0f;
    float total_batch_time_predecessor = 0.0f;
#endif

    fprintf(stderr,
            "Benchmarking %lu operations %lu inserts, %lu deletes, "
            "%lu contains\n",
            NUM_OPS, ADD, REM, FIND);
    // PROSPAR: observation is average occupancy is 20
    // divide by 16 for memory pool reservation
    // #ifndef FIXED_INDEX   GFSL h_skiplist(ADD / 16, false);
    // #else   GFSL h_skiplist(ADD / 16, 15, false);
    // #endif

    GFSL *h_skiplist;
    uint32_t maxNodes = ADD / 12; // worst case each node holds 15 keys
    cudaCheckErrorMacro(cudaMallocManaged(&h_skiplist, sizeof(GFSL)),
                        "Mem allocation failed for h_skiplist");
    Chunk *nodesPool;
    size_t reqSize; // head + one node each level
#if defined(FIXED_INDEX)
    reqSize = (maxNodes * 0.9) + 33;
#elif defined(UNSORTED_IMPL)
    reqSize = maxNodes + 33;
#elif defined(SEPARATE_POOL)
    reqSize = (maxNodes * 0.9) + 33;
#else
    reqSize = maxNodes + 33;
#endif
    cudaCheckErrorMacro(
        cudaMallocManaged((void **)&nodesPool, sizeof(Chunk) * reqSize),
        "Nodes memory allocation pool failure");
    h_skiplist->memory_pool = nodesPool;
#if defined(UVM_MEM_ADVISE_SA)
    cudaCheckErrorMacro(
        cudaMemAdvise(h_skiplist, sizeof(GFSL), cudaMemAdviseSetAccessedBy, 0),
        "Mem advise failed for set accessed by");
#endif
#if defined(UVM_MEM_ADVISE_SP)
    cudaCheckErrorMacro(cudaMemAdvise(h_skiplist, sizeof(GFSL),
                                      cudaMemAdviseSetPreferredLocation, 0),
                        "Mem advise failed for set preferred location");
#endif
#if defined(UVM_MEM_ADVISE_SR)
    cudaCheckErrorMacro(
        cudaMemAdvise(h_skiplist, sizeof(GFSL), cudaMemAdviseSetReadMostly, 0),
        "Mem advise failed for set read mostly");
#endif
#if defined(UVM_PREFETCH_HINT)
    cudaCheckErrorMacro(cudaMemPrefetchAsync(h_skiplist, sizeof(GFSL), 0),
                        "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif

#if defined(UVM_MEM_ADVISE_SA)
    cudaCheckErrorMacro(cudaMemAdvise(h_skiplist->memory_pool,
                                      reqSize * sizeof(Chunk),
                                      cudaMemAdviseSetAccessedBy, 0),
                        "Mem advise SA error for memory pool");
#endif
#if defined(UVM_MEM_ADVISE_SP)
    cudaCheckErrorMacro(cudaMemAdvise(h_skiplist->memory_pool,
                                      reqSize * sizeof(Chunk),
                                      cudaMemAdviseSetPreferredLocation, 0),
                        "Mem advise SP error for memory pool");
#endif
#if defined(UVM_MEM_ADVISE_SR)
    cudaCheckErrorMacro(cudaMemAdvise(h_skiplist->memory_pool,
                                      reqSize * sizeof(Chunk),
                                      cudaMemAdviseSetReadMostly, 0),
                        "Mem advise SR error for memory pool");
#endif
#if defined(UVM_PREFETCH_HINT)
    cudaCheckErrorMacro(cudaMemPrefetchAsync(h_skiplist->memory_pool,
                                             (sizeof(Chunk) * reqSize), 0),
                        "Prefetch hint error for memory pool");
#endif
#if defined(FIXED_INDEX)
    h_skiplist->initializeGFSL(maxNodes, 0.1, false);
#elif defined(UNSORTED_IMPL)
    h_skiplist->initializeGFSL(maxNodes, false);
#elif defined(SEPARATE_POOL)
    h_skiplist->initializeGFSL(maxNodes, 0.1, false);
#else
    h_skiplist->initializeGFSL(maxNodes, false);
#endif
    // TODO: Try memhint only on the half of the memory pool
    // Stats initilization to prevent incorrect node calculation
    SkiplistStats *stats;
    cudaMallocManaged(&stats, sizeof(SkiplistStats));

#if defined(ENABLE_STATS)
    new (stats) SkiplistStats(h_skiplist->pool_size >> 4);
#else
    new (stats) SkiplistStats(1);
#endif

    uint32_t *result = nullptr;
    cudaCheckErrorMacro(
        cudaMallocManaged((void **)&result, sizeof(uint32_t) * ADD),
        "Mem allocation failed for result");
    uint32_t numWarps = 512;

    cudaEvent_t start, stop;
    cudaCheckErrorMacro(cudaEventCreate(&start),
                        "Event creation failed for start event");
    cudaCheckErrorMacro(cudaEventCreate(&stop),
                        "Event creation failed for stop event");

    std::cerr << "Starting insert of " << ADD << " elements\n";

    float insertTime = 0.0f;
    // WARP wait logic
    int *allowWarp = nullptr;
    cudaCheckErrorMacro(
        cudaMallocManaged((void **)&allowWarp, sizeof(int) * WAITING_WARPS),
        "Mem allocation for array warp failed");
    allowWarp[0] = 1; // initially allow only first warp
    std::cout << "Total warps: " << WAITING_WARPS << "\n";
    // std::cout <<"Printing warp access bit ";
    // for(int i = 0; i < WAITING_WARPS; i++) {
    //     std::cout << allowWarp[i] << " ";
    // }
    // std::cout << "\n";
#if defined(BATCH_IMPL)
    uint32_t iter = 0;
    // uint32_t *keys_insert_batch = nullptr;
    // uint32_t *values_insert_batch = nullptr;
    KeyValue *keys_values_batch = nullptr;
    uint32_t *result_batch = nullptr;

    // cudaCheckErrorMacro(cudaMallocManaged((void **)&keys_insert_batch,
    //                                       sizeof(uint32_t) * gpuBatchSize),
    //                     "Mem allocation failed for keys_insert_batch");
    // cudaCheckErrorMacro(cudaMallocManaged((void **)&values_insert_batch,
    //                                       sizeof(uint32_t) * gpuBatchSize),
    //                     "Mem allocation failed for values_insert_batch");
    cudaCheckErrorMacro(cudaMallocManaged((void **)&result_batch,
                                          sizeof(uint32_t) * gpuBatchSize),
                        "Mem allocation failed for result_batch");
    cudaCheckErrorMacro(cudaMallocManaged((void **)&keys_values_batch,
                                          sizeof(KeyValue) * gpuBatchSize),
                        "Mem allocation failed for keys_values_batch");
    // uint64_t totalElements = ADD ;
    uint32_t totalIterations = ADD / gpuBatchSize;
    bool additionalIteration = (ADD % gpuBatchSize) != 0;
    // if not divisible, then more than one iteration
#if defined(OPT_GRID)
    NUM_BLOCKS = 16384;
#else
    // NUM_BLOCKS = (gpuBatchSize + 15) >> 4;
#endif
#if defined(BUSY_WAIT)
    NUM_BLOCKS = (NUM_BLOCKS + KEYS_PER_WARP - 1) / KEYS_PER_WARP;
#endif
    numWarps = NUM_BLOCKS * (BLOCK_SIZE >> 5);

    while (iter < totalIterations) {
      // copy gpuBatchSize elements from keys_insert and values_insert
      auto creationTime = HRClock::now();
      // memcpy(keys_insert_batch, keys_insert + (iter * gpuBatchSize),
      //        sizeof(uint32_t) * gpuBatchSize);
      // memcpy(values_insert_batch, values_insert + (iter * gpuBatchSize),
      //        sizeof(uint32_t) * gpuBatchSize);
      for (uint64_t ind = 0; ind < gpuBatchSize; ind++) {
        keys_values_batch[ind].key =
            keys_values_insert[ind + (iter * gpuBatchSize)].key;
        keys_values_batch[ind].value =
            keys_values_insert[ind + (iter * gpuBatchSize)].value;
      }
      auto creationDuration = HRClock::now() - creationTime;
      total_batch_time_insert += DurationFloatMS(creationDuration).count();
#if defined(UVM_PREFETCH_HINT)
      cudaCheckErrorMacro(cudaMemPrefetchAsync(keys_values_batch,
                                               sizeof(KeyValue) * gpuBatchSize,
                                               0),
                          "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif
#if defined(ENABLE_SORT_INSERT)
      auto startSort = HRClock::now();
      thrust::sort(thrust::cuda::par(alloc), keys_values_batch,
                   keys_values_batch + gpuBatchSize,
                   CompareByRangeShift(power_of_two));
      auto sortTimeInsert = HRClock::now() - startSort;
      total_sort_time_insert += DurationFloatMS(sortTimeInsert).count();
      std::cout << "Time to sort insert batch: "
                << DurationFloatMS(sortTimeInsert).count() << "ms\n";
#endif

      cudaCheckErrorMacro(cudaEventRecord(start, 0),
                          "Event failure for start event");
      batch_insert<<<NUM_BLOCKS, BLOCK_SIZE>>>(
          numWarps, gpuBatchSize, h_skiplist, keys_values_batch, result_batch,
#if defined(BUSY_WAIT)
          allowWarp, KEYS_PER_WARP, WAITING_WARPS,
#endif
          stats);
      cudaCheckErrorMacro(cudaEventRecord(stop, 0),
                          "Event failure for stop event");
      cudaCheckErrorMacro(cudaEventSynchronize(stop),
                          "Event failure for synchronize stop event");
      cudaCheckErrorMacro(cudaEventElapsedTime(&insertTime, start, stop),
                          "Error in calculating elapsed time for insert");
      cout << "Insert time batch " << iter << " : " << insertTime << " ms\n";
      total_insert_time += insertTime;
      iter++;
// #if defined(BUSY_WAIT)
//       for (uint32_t pI = 1; pI < WAITING_WARPS; pI++) {
//         allowWarp[pI] = 0;
//       }
//       allowWarp[0] = 1;
// #endif
#if defined(KEY_CHECK)
      for (uint32_t i = 0; i < gpuBatchSize; i++) {
        if (result_batch[i] != 1) {
          std::cerr << "Something wrong with insert of " << i << " key "
                    << result_batch[i] << "\n";
          std::cout
              << "[ERROR] Experiment terminated due to key check failure\n";
          exit(EXIT_FAILURE);
        }
      }
#endif
    }
    if (additionalIteration) {
      uint64_t remainingElements = ADD % gpuBatchSize;
      auto creationTime = HRClock::now();
#if defined(OPT_GRID)
      NUM_BLOCKS = 16384;
#else
      // NUM_BLOCKS = (remainingElements + 15) >> 4;
#endif
#if defined(BUSY_WAIT)
      NUM_BLOCKS = (NUM_BLOCKS + KEYS_PER_WARP - 1) / KEYS_PER_WARP;
#endif
      numWarps = NUM_BLOCKS * (BLOCK_SIZE >> 5);
      // memcpy(keys_insert_batch, keys_insert + (totalIterations *
      // gpuBatchSize),
      //        sizeof(uint32_t) * remainingElements);
      // memcpy(values_insert_batch,
      //        values_insert + (totalIterations * gpuBatchSize),
      //        sizeof(uint32_t) * remainingElements);
      for (uint64_t ind = 0; ind < remainingElements; ind++) {
        keys_values_batch[ind].key =
            keys_values_insert[ind + (totalIterations * gpuBatchSize)].key;
        keys_values_batch[ind].value =
            keys_values_insert[ind + (totalIterations * gpuBatchSize)].value;
      }
      auto creationDuration = HRClock::now() - creationTime;
      total_batch_time_insert += DurationFloatMS(creationDuration).count();
#if defined(UVM_PREFETCH_HINT)
      cudaCheckErrorMacro(
          cudaMemPrefetchAsync(keys_values_batch,
                               sizeof(KeyValue) * remainingElements, 0),
          "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif
#if defined(ENABLE_SORT_INSERT)
      auto startSort = HRClock::now();
      thrust::sort(thrust::cuda::par(alloc), keys_values_batch,
                   keys_values_batch + remainingElements,
                   CompareByRangeShift(power_of_two));
      auto sortTimeInsert = HRClock::now() - startSort;
      total_sort_time_insert += DurationFloatMS(sortTimeInsert).count();
      std::cout << "Time to sort insert batch: "
                << DurationFloatMS(sortTimeInsert).count() << " ms\n";
#endif
      cudaCheckErrorMacro(cudaEventRecord(start, 0),
                          "Event failure for start event");
      batch_insert<<<NUM_BLOCKS, BLOCK_SIZE>>>(
          numWarps, remainingElements, h_skiplist, /*keys_insert_batch,
        values_insert_batch*/
          keys_values_batch, result_batch,
#if defined(BUSY_WAIT)
          allowWarp, KEYS_PER_WARP, WAITING_WARPS,
#endif
          stats);
      cudaCheckErrorMacro(cudaEventRecord(stop, 0),
                          "Event failure for stop event");
      cudaCheckErrorMacro(cudaEventSynchronize(stop),
                          "Event failure for synchronize stop event");
      cudaCheckErrorMacro(cudaEventElapsedTime(&insertTime, start, stop),
                          "Error in calculating elapsed time");
      cout << "Insert time batch " << iter << " : " << insertTime << " ms\n";
      total_insert_time += insertTime;
#if defined(KEY_CHECK)
      for (uint32_t i = 0; i < remainingElements; i++) {
        if (result_batch[i] != 1) {
          std::cerr << "Insert failed for key " << i << " key "
                    << result_batch[i] << " \n";
          std::cout << "[Error] Key check failed for insert\n";
          exit(EXIT_FAILURE);
        }
      }
#endif
    }
    cudaCheckErrorMacro(cudaFree(result_batch),
                        "Mem free failed for result after insertion");
    cudaCheckErrorMacro(cudaFree(keys_values_batch),
                        "Mem free failed for kv batch after insertion");
#else
#if defined(UVM_PREFETCH_HINT)
    cudaCheckErrorMacro(
        cudaMemPrefetchAsync(keys_values_insert, sizeof(KeyValue) * ADD, 0),
        "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif
#if defined(ENABLE_SORT)
    // thrust use cudaMalloc lead to bad memory allocation on large input set
    auto sortStart = HRClock::now();
    std::sort(std::execution::par_unseq, keys_values_insert,
              keys_values_insert + ADD, compareByRange);
    auto sortDurationInsert = HRClock::now() - sortStart;
    total_sort_time_insert += DurationFloatMS(sortDurationInsert).count();
    std::cout << "Sort duration: "
              << DurationFloatMS(sortDurationInsert).count() << " ms\n";
#endif
#if defined(OPT_GRID)
    NUM_BLOCKS = 16384;
#else
    // NUM_BLOCKS = (ADD + 15) >> 4;
#endif
#if defined(BUSY_WAIT)
    NUM_BLOCKS = (NUM_BLOCKS + KEYS_PER_WARP - 1) / KEYS_PER_WARP;
#endif
    numWarps = NUM_BLOCKS * (BLOCK_SIZE >> 5);
    cudaCheckErrorMacro(cudaEventRecord(start, 0),
                        "Event failure for start event");
    batch_insert<<<NUM_BLOCKS, BLOCK_SIZE>>>(
        numWarps, ADD, h_skiplist, keys_values_insert, result,
#if defined(BUSY_WAIT)
        allowWarp, KEYS_PER_WARP, WAITING_WARPS,
#endif
        stats);
    // numWarps, ADD, h_skiplist, keys_insert, values_insert, result, stats);
    cudaCheckErrorMacro(cudaEventRecord(stop, 0),
                        "Event failure for stop event");
    cudaCheckErrorMacro(cudaEventSynchronize(stop),
                        "Event failure for synchronize stop event");
    cudaCheckErrorMacro(cudaEventElapsedTime(&insertTime, start, stop),
                        "Error in calculating elapsed time");
    std::cerr << "Finished insert in: " << insertTime << "\n";
    total_insert_time += insertTime;
#if defined(KEY_CHECK)
    for (uint32_t i = 0; i < ADD; i++) {

      if (result[i] != 1) {
        std::cerr << "[Error] Insert failed for key " << i
                  << " :: " << result[i] << " \n";
        std::cout
            << "[Error] Execution failed due to key check failure in insert\n";
        exit(EXIT_FAILURE);
      }
    }
    std::cout << "Insert check completed\n";
#endif
    cudaCheckErrorMacro(cudaFree(result),
                        "Mem free failed for result after insert");

#endif
    // std::cout <<"Printing warp access after insert ";
    // for(int i=0; i< WAITING_WARPS; i++) {
    //     std::cout << allowWarp[i] << " ";
    // }
    if (REM) {
      std::cerr << "Starting delete of " << REM << " elements\n";

      float deleteTime = 0.0f;
#if defined(BATCH_IMPL)
      uint32_t iter = 0;
      uint32_t *keys_del_batch = nullptr;
      uint32_t *result_batch = nullptr;

      cudaCheckErrorMacro(cudaMallocManaged((void **)&keys_del_batch,
                                            sizeof(uint32_t) * gpuBatchSize),
                          "Mem allocation failed for keys_del_batch");
      cudaCheckErrorMacro(cudaMallocManaged((void **)&result_batch,
                                            sizeof(uint32_t) * gpuBatchSize),
                          "Mem allocation failed for result_batch");
      // uint64_t totalElements = REM ;
      uint32_t totalIterations = REM / gpuBatchSize;
      bool additionalIteration = (REM % gpuBatchSize) != 0;
      NUM_BLOCKS = (gpuBatchSize + 15) >> 4;
      numWarps = ((NUM_BLOCKS + KEYS_PER_WARP - 1) / KEYS_PER_WARP) *
                 (BLOCK_SIZE >> 5);
      while (iter < totalIterations) {
        // copy gpuBatchSize elements from keys_del
        auto creationTime = HRClock::now();
        memcpy(keys_del_batch, keys_del + (iter * gpuBatchSize),
               sizeof(uint32_t) * gpuBatchSize);
        auto creationDuration = HRClock::now() - creationTime;
        total_batch_time_delete += DurationFloatMS(creationDuration).count();
#if defined(UVM_PREFETCH_HINT)
        cudaCheckErrorMacro(
            cudaMemPrefetchAsync(keys_del_batch,
                                 sizeof(uint32_t) * gpuBatchSize, 0),
            "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif
#if defined(ENABLE_SORT)
        auto startSortDelete = HRClock::now();
        thrust::sort(thrust::cuda::par(alloc), keys_del_batch,
                     keys_del_batch + gpuBatchSize,
                     CompareByRangeShiftDS(power_of_two));
        auto sortTimeDelete = HRClock::now() - startSortDelete;
        total_sort_time_delete += DurationFloatMS(sortTimeDelete).count();
        std::cout << "Time to sort delete batch: "
                  << DurationFloatMS(sortTimeDelete).count() << "ms\n";
#endif

        cudaCheckErrorMacro(cudaEventRecord(start, 0),
                            "Event failure for start event");
        batch_delete<<<NUM_BLOCKS, BLOCK_SIZE>>>(
            numWarps, gpuBatchSize, h_skiplist, keys_del_batch, result_batch,
#if defined(BUSY_WAIT)
            allowWarp, KEYS_PER_WARP, WAITING_WARPS,
#endif
            stats);
        cudaCheckErrorMacro(cudaEventRecord(stop, 0),
                            "Event failure for stop event");
        cudaCheckErrorMacro(cudaEventSynchronize(stop),
                            "Event failure for synchronize stop event");
        cudaCheckErrorMacro(cudaEventElapsedTime(&deleteTime, start, stop),
                            "Error in calculating elapsed time");
        total_delete_time += deleteTime;
        cout << "Delete time for batch " << iter << " : " << deleteTime
             << " ms\n";
        iter++;
// TODO: should implement busy wait for delete as well?
// #if defined(BUSY_WAIT)
//         for (uint32_t pI = 1; pI < WAITING_WARPS; pI++) {
//           allowWarp[pI] = 0;
//         }
//         allowWarp[0] = 1;
// #endif
#if defined(KEY_CHECK)
        for (uint32_t i = 0; i < gpuBatchSize; i++) {
          if (result_batch[i] != 1) {
            std::cerr << "Something wrong with delete " << result_batch[i]
                      << " \n";
            std::cout << "[Error] Experiment terminated due to key check "
                         "failure in delete\n";
            exit(EXIT_FAILURE);
          }
        }
#endif
      }
      if (additionalIteration) {
        uint64_t remainingElements = REM % gpuBatchSize;
        auto creationTime = HRClock::now();
        memcpy(keys_del_batch, keys_del + (totalIterations * gpuBatchSize),
               sizeof(uint32_t) * remainingElements);
        auto creationDuration = HRClock::now() - creationTime;
        total_batch_time_delete += DurationFloatMS(creationDuration).count();
#if defined(UVM_PREFETCH_HINT)
        cudaCheckErrorMacro(
            cudaMemPrefetchAsync(keys_del_batch,
                                 sizeof(uint32_t) * remainingElements, 0),
            "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif
#if defined(ENABLE_SORT)
        auto sortStartDelete = HRClock::now();
        thrust::sort(thrust::cuda::par(alloc), keys_del_batch,
                     keys_del_batch + remainingElements,
                     CompareByRangeShiftDS(power_of_two));
        auto sortTimeDelete = HRClock::now() - sortStartDelete;
        total_sort_time_delete += DurationFloatMS(sortTimeDelete).count();
        std::cout << "Time to sort delete batch: "
                  << DurationFloatMS(sortTimeDelete).count() << "ms\n";
#endif
        NUM_BLOCKS = (remainingElements + 15) >> 4;
        numWarps = ((NUM_BLOCKS + KEYS_PER_WARP - 1) / KEYS_PER_WARP) *
                   (BLOCK_SIZE >> 5);
        cudaCheckErrorMacro(cudaEventRecord(start, 0),
                            "Event failure for start event");
        batch_delete<<<NUM_BLOCKS, BLOCK_SIZE>>>(
            numWarps, remainingElements, h_skiplist, keys_del_batch,
            result_batch,
#if defined(BUSY_WAIT)
            allowWarp, KEYS_PER_WARP, WAITING_WARPS,
#endif
            stats);
        cudaCheckErrorMacro(cudaEventRecord(stop, 0),
                            "Event failure for stop event");
        cudaCheckErrorMacro(cudaEventSynchronize(stop),
                            "Event failure for synchronize stop event");
        cudaCheckErrorMacro(cudaEventElapsedTime(&deleteTime, start, stop),
                            "Error in calculating elapsed time");
        total_delete_time += deleteTime;
        cout << "Delete time for batch " << iter << " : " << deleteTime
             << " ms\n";
#if defined(KEY_CHECK)
        for (uint32_t i = 0; i < remainingElements; i++) {
          if (result_batch[i] != 1) {
            std::cerr << "Something wrong with delete " << result_batch[i]
                      << " \n";
            std::cout << "[Error] Experiment failed due to key check failure "
                         "in delete\n";
            exit(EXIT_FAILURE);
          }
        }
#endif
      }
      cudaCheckErrorMacro(cudaFree(result_batch),
                          "Mem free failed for result batch after delete");
      cudaCheckErrorMacro(cudaFree(keys_del_batch),
                          "Mem free failed for delete batch after delete");
#else
#if defined(UVM_PREFETCH_HINT)
      cudaCheckErrorMacro(
          cudaMemPrefetchAsync(keys_del, sizeof(uint32_t) * REM, 0),
          "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif
#if defined(ENABLE_SORT)
      auto sortStart = HRClock::now();
      std::sort(std::execution::par_unseq, keys_del, keys_del + REM,
                compareByRangeDS);
      auto sortDuration = HRClock::now() - sortStart;
      total_sort_time_delete += DurationFloatMS(sortDuration).count();
      std::cout << "Sort duration: " << DurationFloatMS(sortDuration).count()
                << " ms\n";
#endif
      cudaCheckErrorMacro(
          cudaMallocManaged((void **)&result, sizeof(uint32_t) * REM),
          "Mem allocation failed for result");
      NUM_BLOCKS = (REM + 15) >> 4;
      numWarps = ((NUM_BLOCKS + KEYS_PER_WARP - 1) / KEYS_PER_WARP) *
                 (BLOCK_SIZE >> 5);
      cudaEventRecord(start, 0);
      batch_delete<<<NUM_BLOCKS, BLOCK_SIZE>>>(
          numWarps, REM, h_skiplist, keys_del, result,
#if defined(BUSY_WAIT)
          allowWarp, KEYS_PER_WARP, WAITING_WARPS,
#endif
          stats);
      cudaCheckErrorMacro(cudaEventRecord(stop, 0),
                          "Event failure for stop event");
      cudaCheckErrorMacro(cudaEventSynchronize(stop),
                          "Event failure for synchronize stop event");
      cudaCheckErrorMacro(cudaEventElapsedTime(&deleteTime, start, stop),
                          "Error in calculating elapsed time");
      std::cerr << "Finished delete in: " << deleteTime << "\n";
      total_delete_time += deleteTime;
#if defined(KEY_CHECK)
      for (uint32_t i = 0; i < REM; i++) {
        if (result[i] != 1) {
          std::cerr << "Something wrong with delete\n";
          std::cerr << "result[" << i << "] is " << result[i] << std::endl;
          std::cout
              << "[Error] Experiment failed due key check failure in delete\n";
          break;
        }
        // else {
        //   for (uint32_t j = 0; j < ADD; j++) {
        //     if (keyCheckArr[j] == keys_del[i])
        //       keyCheckArr[j] = 0; // successful deletion
        //   }
        // }
      }
      //       std::cerr << "Starting delete correctness check by launching
      //       contains..."
      //                 << std::endl;
      //       batch_contains<<<NUM_BLOCKS, BLOCK_SIZE>>>(numWarps, REM,
      //       h_skiplist,
      //                                                  keys_del, result,
      // #if defined(BUSY_WAIT_SEARCH)
      //                                                  KEYS_PER_WARP,
      // #endif
      //                                                  stats);
      //       for (int i = 0; i < REM; i++) {
      //         if (result[i] != -1) {
      //           std::cerr << "Something wrong with delete\n";
      //           std::cerr << "result[" << i << "] is " << result[i] <<
      //           std::endl; std::cerr << "Note: key for deletion was " <<
      //           keys_del[i]
      //                     << std::endl;
      //         }
      //       }
      // std::cerr << "Searching each level for deleted keys..." << std::endl;

      // delete_kernel_correctness_check<<<NUM_BLOCKS, BLOCK_SIZE>>>(
      //     numWarps, REM, h_skiplist, keys_del, result);

      // for (int i = 0; i < REM; i++) {
      //   if (!result[i]) {
      //     std::cerr << "Key " << keys_del[i]
      //               << " was not completely deleted from the list "
      //               << std::endl;
      //   }
      // }
      std::cerr << "Delete correctness check completed" << std::endl;
#endif
      cudaCheckErrorMacro(cudaFree(result),
                          "Mem free failed for result after delete");
#endif
    }

    //     auto kv_pair = init_cons_key_vals(keys.get(), vals.get(),
    //     conf.num_deletes, conf.num_contains); auto cons_keys =
    //     std::move(kv_pair.first); auto cons_vals = std::move(kv_pair.second);
    //     conf.num_contains);
    // TODO: verification of contains
    // uint32_t *cons_vals = trace.c_res_arr;

    float containsTime = 0.0f;
    if (FIND && (!PREDECESSOR_SEARCH)) {
      std::cerr << "Starting search of " << FIND << " elements\n";

#if defined(BATCH_IMPL)
      uint32_t iter = 0;
      uint32_t *keys_lookup_batch = nullptr;
      uint32_t *result_batch = nullptr;

      cudaCheckErrorMacro(cudaMallocManaged((void **)&keys_lookup_batch,
                                            sizeof(uint32_t) * gpuBatchSize),
                          "Mem allocation failed for keys_lookup_batch");
      cudaCheckErrorMacro(cudaMallocManaged((void **)&result_batch,
                                            sizeof(uint32_t) * gpuBatchSize),
                          "Mem allocation failed for result_batch");
      // uint64_t totalElements = FIND ;
      uint32_t totalIterations = FIND / gpuBatchSize;
      bool additionalIteration = (FIND % gpuBatchSize) != 0;
      NUM_BLOCKS = (gpuBatchSize + 15) >> 4;
#if defined(BUSY_WAIT_SEARCH)
      NUM_BLOCKS = (NUM_BLOCKS + KEYS_PER_WARP - 1) / KEYS_PER_WARP;
#endif
      numWarps = NUM_BLOCKS * (BLOCK_SIZE >> 5);
      while (iter < totalIterations) {
        // copy gpuBatchSize elements from keys_lookup
        auto creationTime = HRClock::now();
        memcpy(keys_lookup_batch, keys_lookup + (iter * gpuBatchSize),
               sizeof(uint32_t) * gpuBatchSize);
        auto creationDuration = HRClock::now() - creationTime;
        total_batch_time_search += DurationFloatMS(creationDuration).count();
#if defined(UVM_PREFETCH_HINT)
        cudaCheckErrorMacro(
            cudaMemPrefetchAsync(keys_lookup_batch,
                                 sizeof(uint32_t) * gpuBatchSize, 0),
            "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif
#if defined(ENABLE_SORT)
        auto sortStartSearch = HRClock::now();
        thrust::sort(thrust::device, keys_lookup_batch,
                     keys_lookup_batch + gpuBatchSize,
                     CompareByRangeShiftDS(power_of_two));
        auto sortTimeSearch = HRClock::now() - sortStartSearch;
        total_sort_time_search += DurationFloatMS(sortTimeSearch).count();
        std::cout << "Time to sort search batch: "
                  << DurationFloatMS(sortTimeSearch).count() << " ms\n";
#endif
        cudaCheckErrorMacro(cudaEventRecord(start, 0),
                            "Event failure for start event");
        batch_contains<<<NUM_BLOCKS, BLOCK_SIZE>>>(
            numWarps, gpuBatchSize, h_skiplist, keys_lookup_batch, result_batch,
#if defined(BUSY_WAIT_SEARCH)
            KEYS_PER_WARP,
#endif
            stats);
        cudaCheckErrorMacro(cudaEventRecord(stop, 0),
                            "Event failure for stop event");
        cudaCheckErrorMacro(cudaEventSynchronize(stop),
                            "Event failure for synchronize stop event");
        cudaCheckErrorMacro(cudaEventElapsedTime(&containsTime, start, stop),
                            "Error in calculating elapsed time");
        total_search_time += containsTime;
        cout << "Search time for batch " << iter << " : " << containsTime
             << " ms\n";
        iter++;
      }
      if (additionalIteration) {
        uint64_t remainingElements = FIND % gpuBatchSize;
        auto creationTime = HRClock::now();
        memcpy(keys_lookup_batch,
               keys_lookup + (totalIterations * gpuBatchSize),
               sizeof(uint32_t) * remainingElements);
        auto creationDuration = HRClock::now() - creationTime;
        total_batch_time_search += DurationFloatMS(creationDuration).count();
#if defined(UVM_PREFETCH_HINT)
        cudaCheckErrorMacro(
            cudaMemPrefetchAsync(keys_lookup_batch,
                                 sizeof(uint32_t) * remainingElements, 0),
            "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif
#if defined(ENABLE_SORT)
        auto sortStartSearch = HRClock::now();
        thrust::sort(thrust::device, keys_lookup_batch,
                     keys_lookup_batch + remainingElements,
                     CompareByRangeShiftDS(power_of_two));
        auto sortTimeSearch = HRClock::now() - sortStartSearch;
        total_sort_time_search += DurationFloatMS(sortTimeSearch).count();
        std::cout << "Time to sort search batch: "
                  << DurationFloatMS(sortTimeSearch).count() << " ms\n";
#endif
        NUM_BLOCKS = (remainingElements + 15) >> 4;
#if defined(BUSY_WAIT_SEARCH)
        NUM_BLOCKS = (NUM_BLOCKS + KEYS_PER_WARP - 1) / KEYS_PER_WARP;
#endif
        numWarps = NUM_BLOCKS * (BLOCK_SIZE >> 5);
        cudaCheckErrorMacro(cudaEventRecord(start, 0),
                            "Event failure for start event");

        batch_contains<<<NUM_BLOCKS, BLOCK_SIZE>>>(
            numWarps, remainingElements, h_skiplist, keys_lookup_batch,
            result_batch,
#if defined(BUSY_WAIT_SEARCH)
            KEYS_PER_WARP,
#endif
            stats);

        cudaCheckErrorMacro(cudaEventRecord(stop, 0),
                            "Event failure for stop event");
        cudaCheckErrorMacro(cudaEventSynchronize(stop),
                            "Event failure for synchronize stop event");
        cudaCheckErrorMacro(cudaEventElapsedTime(&containsTime, start, stop),
                            "Error in calculating elapsed time");
        total_search_time += containsTime;
        cout << "Search time for batch " << iter << " : " << containsTime
             << " ms\n";
      }
      cudaCheckErrorMacro(cudaFree(result_batch),
                          "Mem free failed for result batch after contains");
      cudaCheckErrorMacro(cudaFree(keys_lookup_batch),
                          "Mem free failed for search batch after contains");
#else
#if defined(UVM_PREFETCH_HINT)
      cudaCheckErrorMacro(
          cudaMemPrefetchAsync(keys_lookup, sizeof(uint32_t) * FIND, 0),
          "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif
#if defined(ENABLE_SORT)
      auto sortStart = HRClock::now();
      std::sort(std::execution::par_unseq, keys_lookup, keys_lookup + FIND,
                compareByRangeDS);
      auto sortDuration = HRClock::now() - sortStart;
      total_sort_time_search += DurationFloatMS(sortDuration).count();
      std::cout << "Sort duration: " << DurationFloatMS(sortDuration).count()
                << " ms\n";
#endif
      NUM_BLOCKS = (FIND + 15) >> 4;
#if defined(BUSY_WAIT_SEARCH)
      NUM_BLOCKS = (NUM_BLOCKS + KEYS_PER_WARP - 1) / KEYS_PER_WARP;
#endif
      numWarps = NUM_BLOCKS * (BLOCK_SIZE >> 5);
      cudaCheckErrorMacro(
          cudaMallocManaged((void **)&result, sizeof(uint32_t) * FIND),
          "Mem allocation failed for result");
      cudaEventRecord(start, 0);
      batch_contains<<<NUM_BLOCKS, BLOCK_SIZE>>>(numWarps, FIND, h_skiplist,
                                                 keys_lookup, result,
#if defined(BUSY_WAIT_SEARCH)
                                                 KEYS_PER_WARP,
#endif
                                                 stats);

      cudaCheckErrorMacro(cudaDeviceSynchronize(),
                          "Device synchronize failed after contains kernel");
      cudaCheckErrorMacro(cudaEventRecord(stop, 0),
                          "Event failure for stop event");
      cudaCheckErrorMacro(cudaEventSynchronize(stop),
                          "Event failure for synchronize stop event");
      cudaCheckErrorMacro(cudaEventElapsedTime(&containsTime, start, stop),
                          "Error in calculating elapsed time");
      std::cerr << "Finished contains in: " << containsTime << "\n";
      std::cout << containsTime << std::endl;
      total_search_time += containsTime;
#if defined(KEY_CHECK)
      std::cerr << "Checking contains results...\n";
      // too slow key check for large search queries
      //  for (uint32_t sInd = 0; sInd < FIND; sInd++) {
      //    for (uint32_t aInd = 0; aInd < ADD; aInd++)
      //      if (keys_values_insert[aInd].key == keys_lookup[sInd]) {
      //        if (result[sInd] != 0)
      //          assert(result[sInd] == keys_values_insert[aInd].value);
      //        break;
      //      }
      //  }
      //  free(cons_vals);
#endif
      cudaCheckErrorMacro(cudaFree(result),
                          "Mem free failed for result after contains");
#endif
    } // FIND
    float predecessorTime = 0.0f;
    if (FIND && PREDECESSOR_SEARCH) {
      std::cerr << "Starting predecessor search of " << FIND << " elements\n";

#if defined(BATCH_IMPL)
      uint32_t iter = 0;
      uint32_t *keys_lookup_batch = nullptr;
      uint32_t *result_batch = nullptr;

      cudaCheckErrorMacro(cudaMallocManaged((void **)&keys_lookup_batch,
                                            sizeof(uint32_t) * gpuBatchSize),
                          "Mem allocation failed for keys_lookup_batch");
      cudaCheckErrorMacro(cudaMallocManaged((void **)&result_batch,
                                            sizeof(uint32_t) * gpuBatchSize),
                          "Mem allocation failed for result_batch");
      // uint64_t totalElements = FIND ;
      uint32_t totalIterations = FIND / gpuBatchSize;
      bool additionalIteration = (FIND % gpuBatchSize) != 0;
      NUM_BLOCKS = (gpuBatchSize + 15) >> 4;
#if defined(BUSY_WAIT_SEARCH)
      NUM_BLOCKS = (NUM_BLOCKS + KEYS_PER_WARP - 1) / KEYS_PER_WARP;
#endif
      numWarps = NUM_BLOCKS * (BLOCK_SIZE >> 5);

      while (iter < totalIterations) {
        // copy gpuBatchSize elements from keys_lookup
        auto creationTime = HRClock::now();
        memcpy(keys_lookup_batch, keys_lookup + (iter * gpuBatchSize),
               sizeof(uint32_t) * gpuBatchSize);
        auto creationDuration = HRClock::now() - creationTime;
        total_batch_time_predecessor +=
            DurationFloatMS(creationDuration).count();
#if defined(UVM_PREFETCH_HINT)
        cudaCheckErrorMacro(
            cudaMemPrefetchAsync(keys_lookup_batch,
                                 sizeof(uint32_t) * gpuBatchSize, 0),
            "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif
#if defined(ENABLE_SORT)
        auto sortStartSearch = HRClock::now();
        thrust::sort(thrust::device, keys_lookup_batch,
                     keys_lookup_batch + gpuBatchSize,
                     CompareByRangeShiftDS(power_of_two));
        auto sortTimeSearch = HRClock::now() - sortStartSearch;
        total_sort_time_predecessor += DurationFloatMS(sortTimeSearch).count();
        std::cout << "Time to sort search batch: "
                  << DurationFloatMS(sortTimeSearch).count() << " ms\n";
#endif
        cudaCheckErrorMacro(cudaEventRecord(start, 0),
                            "Event failure for start event");
        batch_predecessor<<<NUM_BLOCKS, BLOCK_SIZE>>>(
            numWarps, gpuBatchSize, h_skiplist, keys_lookup_batch, result_batch,
#if defined(BUSY_WAIT_SEARCH)
            KEYS_PER_WARP,
#endif
            stats);
        cudaCheckErrorMacro(cudaEventRecord(stop, 0),
                            "Event failure for stop event");
        cudaCheckErrorMacro(cudaEventSynchronize(stop),
                            "Event failure for synchronize stop event");
        cudaCheckErrorMacro(cudaEventElapsedTime(&predecessorTime, start, stop),
                            "Error in calculating elapsed time");
        total_predecessor_time += predecessorTime;
        cout << "Predecessor search time for batch " << iter << " : "
             << predecessorTime << " ms\n";
        iter++;
      }
      if (additionalIteration) {
        uint64_t remainingElements = FIND % gpuBatchSize;
        auto creationTime = HRClock::now();
        memcpy(keys_lookup_batch,
               keys_lookup + (totalIterations * gpuBatchSize),
               sizeof(uint32_t) * remainingElements);
        auto creationDuration = HRClock::now() - creationTime;
        total_batch_time_predecessor +=
            DurationFloatMS(creationDuration).count();
#if defined(UVM_PREFETCH_HINT)
        cudaCheckErrorMacro(
            cudaMemPrefetchAsync(keys_lookup_batch,
                                 sizeof(uint32_t) * remainingElements, 0),
            "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif
#if defined(ENABLE_SORT)
        auto sortStartSearch = HRClock::now();
        thrust::sort(thrust::device, keys_lookup_batch,
                     keys_lookup_batch + remainingElements,
                     CompareByRangeShiftDS(power_of_two));
        auto sortTimeSearch = HRClock::now() - sortStartSearch;
        total_sort_time_predecessor += DurationFloatMS(sortTimeSearch).count();
        std::cout << "Time to sort search batch: "
                  << DurationFloatMS(sortTimeSearch).count() << " ms\n";
#endif
        NUM_BLOCKS = (remainingElements + 15) >> 4;
#if defined(BUSY_WAIT_SEARCH)
        NUM_BLOCKS = (NUM_BLOCKS + KEYS_PER_WARP - 1) / KEYS_PER_WARP;
#endif
        numWarps = NUM_BLOCKS * (BLOCK_SIZE >> 5);
        cudaCheckErrorMacro(cudaEventRecord(start, 0),
                            "Event failure for start event");
        batch_predecessor<<<NUM_BLOCKS, BLOCK_SIZE>>>(
            numWarps, remainingElements, h_skiplist, keys_lookup_batch,
            result_batch,
#if defined(BUSY_WAIT_SEARCH)
            KEYS_PER_WARP,
#endif
            stats);

        cudaCheckErrorMacro(cudaEventRecord(stop, 0),
                            "Event failure for stop event");
        cudaCheckErrorMacro(cudaEventSynchronize(stop),
                            "Event failure for synchronize stop event");
        cudaCheckErrorMacro(cudaEventElapsedTime(&predecessorTime, start, stop),
                            "Error in calculating elapsed time");
        total_predecessor_time += predecessorTime;
        cout << "Predecessor search time for batch " << iter << " : "
             << predecessorTime << " ms\n";
      }
      cudaCheckErrorMacro(cudaFree(result_batch),
                          "Mem free failed for result batch");
      cudaCheckErrorMacro(cudaFree(keys_lookup_batch),
                          "Mem free failed for predecessor batch");
#else
#if defined(UVM_PREFETCH_HINT)
      cudaCheckErrorMacro(
          cudaMemPrefetchAsync(keys_lookup, sizeof(uint32_t) * FIND, 0),
          "Mem prefetch failed for UVM_PREFETCH_HINT");
#endif
#if defined(ENABLE_SORT)
      auto sortStart = HRClock::now();
      std::sort(std::execution::par_unseq, keys_lookup, keys_lookup + FIND,
                compareByRangeDS);
      auto sortDuration = HRClock::now() - sortStart;
      total_sort_time_predecessor += DurationFloatMS(sortDuration).count();
      std::cout << "Sort duration: " << DurationFloatMS(sortDuration).count()
                << " ms\n";
#endif
      NUM_BLOCKS = (FIND + 15) >> 4;
#if defined(BUSY_WAIT_SEARCH)
      NUM_BLOCKS = (NUM_BLOCKS + KEYS_PER_WARP - 1) / KEYS_PER_WARP;
#endif
      numWarps = NUM_BLOCKS * (BLOCK_SIZE >> 5);
      cudaCheckErrorMacro(
          cudaMallocManaged((void **)&result, sizeof(uint32_t) * FIND),
          "Mem allocation failed for result");
      cudaEventRecord(start, 0);
      batch_predecessor<<<NUM_BLOCKS, BLOCK_SIZE>>>(numWarps, FIND, h_skiplist,
                                                    keys_lookup, result,
#if defined(BUSY_WAIT_SEARCH)
                                                    KEYS_PER_WARP,
#endif
                                                    stats);

      cudaCheckErrorMacro(cudaDeviceSynchronize(),
                          "Device synchronize failed after predecessor kernel");
      cudaCheckErrorMacro(cudaEventRecord(stop, 0),
                          "Event failure for stop event");
      cudaCheckErrorMacro(cudaEventSynchronize(stop),
                          "Event failure for synchronize stop event");
      cudaCheckErrorMacro(cudaEventElapsedTime(&predecessorTime, start, stop),
                          "Error in calculating elapsed time");
      std::cerr << "Finished predecessor search in: " << predecessorTime
                << "\n";
      // std::cout << predecessorTime << std::endl;
      total_predecessor_time += predecessorTime;
#if defined(KEY_CHECK)

      for (uint32_t i = 0; i < FIND; i++) {
        if (result[i] && (result[i] < keys_lookup[i])) {
          continue;
        } else if (result[i] == 0) {
          std::cerr << "No predecessor found for key " << keys_lookup[i]
                    << "\n";
        } else {
          std::cerr << "Something wrong with predecessor search for key "
                    << keys_lookup[i] << " got " << result[i] << std::endl;
        }
      }
#endif
      cudaCheckErrorMacro(cudaFree(result),
                          "Mem free failed for result after delete");
#endif
    } // PREDECESSOR_SEARCH

#if defined(ENABLE_STATS)
    stats->printStats(h_skiplist->pool_size);
#endif
    uint32_t *lastKey = nullptr;
    cudaCheckErrorMacro(cudaMallocManaged((void **)&lastKey, sizeof(uint32_t)),
                        "Mem allocation failed for lastKey");
    findLastKey<<<1, 32>>>(h_skiplist, lastKey);
    cudaCheckErrorMacro(cudaDeviceSynchronize(),
                        "Device synchronize failed after findLastKey kernel");
    std::cerr << "Last Key in the Skiplist: " << lastKey[0] << std::endl;
    cudaCheckErrorMacro(cudaFree(lastKey), "Mem free failed for lastKey");
    uint32_t *firstKey = nullptr;
    cudaCheckErrorMacro(cudaMallocManaged((void **)&firstKey, sizeof(uint32_t)),
                        "Mem allocation failed for firstKey");
    findFirstKey<<<1, 32>>>(h_skiplist, firstKey);
    cudaCheckErrorMacro(cudaDeviceSynchronize(),
                        "Device synchronize failed after findFirstKey kernel");
    std::cerr << "First Key in the Skiplist: " << firstKey[0] << std::endl;
    cudaCheckErrorMacro(cudaFree(firstKey), "Mem free failed for firstKey");
    // h_skiplist->print(true);
    h_skiplist->freeGFSL();
    cudaCheckErrorMacro(cudaFree(h_skiplist), "Mem free failed for h_skiplist");
    std::cerr << "Total insert time for all batches: " << total_insert_time
              << std::endl;
    std::cerr << "Total delete time for all batches: " << total_delete_time
              << std::endl;
    std::cerr << "Total search time for all batches: " << total_search_time
              << std::endl;
    std::cerr << "Total predecessor time for all batches: "
              << total_predecessor_time << std::endl;
    total_sort_time = total_sort_time_insert + total_sort_time_delete +
                      total_sort_time_search + total_sort_time_predecessor;
    std::cerr << "Total time for sorting insert keys:" << total_sort_time_insert
              << std::endl;
    std::cerr << "Total time for sorting delete keys:" << total_sort_time_delete
              << std::endl;
    std::cerr << "Total time for sorting search keys:" << total_sort_time_search
              << std::endl;
    std::cerr << "Total time for sorting predecessor search keys:"
              << total_sort_time_predecessor << std::endl;
    std::cerr << "Total time for sorting batches: " << total_sort_time
              << std::endl;
#if defined(BATCH_IMPL)
    total_batch_time = total_batch_time_insert + total_batch_time_delete +
                       total_batch_time_search + total_batch_time_predecessor;

    std::cerr << "Total time for creating insert batches: "
              << total_batch_time_insert << std::endl;
    std::cerr << "Total time for creating delete batches: "
              << total_batch_time_delete << std::endl;
    std::cerr << "Total time for creating search batches: "
              << total_batch_time_search << std::endl;
    std::cerr << "Total time for creating predecessor batches: "
              << total_batch_time_predecessor << std::endl;
    std::cerr << "Total time for creating batches: " << total_batch_time
              << std::endl;

#endif
    total_time = total_insert_time + total_delete_time + total_search_time +
                 total_predecessor_time + total_batch_time + total_sort_time;
    std::cerr << "Total time for all batches: " << total_time << std::endl;

    iterTimes.push_back({iterPerLaunch, total_time, total_insert_time,
                         total_delete_time, total_search_time,
                         total_predecessor_time, total_batch_time,
                         total_sort_time});
    cudaCheckErrorMacro(cudaMemGetInfo(&free, &tot),
                        "Error in getting memory info");

    std::cerr << "Free memory: " << (free >> 20) << " MB\n";
    std::cerr << "Total memory: " << (tot >> 20) << " MB\n";
    std::cerr << "Occupied memory: " << ((tot - free) >> 20) << " MB\n";
  } // end of iterations
#if defined(ENABLE_SORT)
  alloc.reset();
#endif
  // sort the iteration times based on total time
  std::sort(iterTimes.begin(), iterTimes.end(),
            [](const iterationTime &a, const iterationTime &b) {
              return a.total_time < b.total_time;
            });
  // Find the median of the vector iterTimes and print the fields
  size_t medianIndex = iterTimes.size() / 2;
  iterationTime median = iterTimes[medianIndex];

  std::cerr << "Median Iteration: " << median.iteration << std::endl;
  std::cerr << "Median Total Time: " << median.total_time << " ms" << std::endl;
  std::cerr << "Median Insert Time: " << median.total_insert_time << " ms"
            << std::endl;
  std::cerr << "Median Delete Time: " << median.total_delete_time << " ms"
            << std::endl;
  std::cerr << "Median Search Time: " << median.total_search_time << " ms"
            << std::endl;
  std::cerr << "Median Predecessor Time: " << median.total_predecessor_time
            << " ms" << std::endl;
  std::cerr << "Median Batch Time: " << median.total_batch_time << " ms"
            << std::endl;
  std::cerr << "Median Sort Time: " << median.total_sort_time << " ms"
            << std::endl;

  // info to identify successfull experiment
  std::cout << "[info] Experiment completed successfully\n";

  if (OVERSUB_RATIO)
    release_reservations(reservations);

  return 0;
}
