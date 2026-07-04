#include "constants.h"
#include "functions.h"
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>

#include "global-vars.h"
#if defined(CG)
#include "gpu_part_batch_HoH_CG.cuh"
#else
#include "gpu_part_batch_HoH.cuh"
#endif

#if defined(FSORT)
#include <algorithm>
#include <execution>
#endif

#if defined(BSORT)
#include <thrust/device_ptr.h>
#include <thrust/execution_policy.h>
#include <thrust/sort.h>
#endif

using std::cerr;
using std::cout;
using std::endl;
using std::string;
using std::vector;

using HRClock = std::chrono::high_resolution_clock;
using DurationFloatMS = std::chrono::duration<float, std::milli>;

int main(int argc, char *argv[]) {

#if defined(FSORT) && defined(BSORT)
  printf("Both batch sort and full sort cannot be used together. Program "
         "exiting......\n");
  return EXIT_FAILURE;
#endif
  for (uint32_t i = 1; i < argc; i++) {
    int error = parse_args(argv[i]);
    if (error == 1) {
      cout << "[ERROR] Argument error, terminating run.\n";
      exit(EXIT_FAILURE);
    }
  }

  std::srand(RANDOM_SEED);
  assert(NUM_ADD_OPS > 0);
  uint64_t NUM_FIND_OPS = NUM_OPS - (NUM_ADD_OPS + NUM_REM_OPS);

  cout << "NUM_OPS: " << NUM_OPS << " NUM_ADD_OPS: " << NUM_ADD_OPS
       << " NUM_REM_OPS: " << NUM_REM_OPS << " NUM_FIND_OPS: " << NUM_FIND_OPS
       << "\n";

  // CPU copies of insert, delete, and search arrays

  // CPU copies of insert, delete, and search arrays
  auto *cpu_kvs_insert = new KeyValue[NUM_ADD_OPS];
  uint32_t *cpu_keys_del = nullptr;
  if (NUM_REM_OPS > 0) {
    cpu_keys_del = new uint32_t[NUM_REM_OPS];
  }
  uint32_t *cpu_keys_lookup = nullptr;
  if (NUM_FIND_OPS) {
    cpu_keys_lookup = new uint32_t[NUM_FIND_OPS];
  }

  path cwd = std::filesystem::current_path();
  // read the operation list from trace
  if (USE_TRACE_FILE) {
    checkTraceFiles(addTrace, delTrace, findTrace, cpu_kvs_insert, cpu_keys_del,
                    cpu_keys_lookup);
  } else { // generate input on run using rand()
    // Use "rand()%(max_val-min_val + 1)+min_val" to generate in random numbers
    // in the range (min, max). For us, it is [1, UINT32_MAX].

    uint64_t add = 0;
    while (add < NUM_ADD_OPS) {
      cpu_kvs_insert[add].key = rand() % ((UINT32_MAX - 1) + 1) + 1;
      cpu_kvs_insert[add].value = rand() % ((UINT32_MAX - 1) + 1) + 1;
      add++;
    }
    uint64_t rem = 0;
    while (rem < NUM_REM_OPS) {
      cpu_keys_del[rem] = rand() % ((UINT32_MAX - 1) + 1) + 1;
      rem++;
    }
    uint64_t find = 0;
    while (find < NUM_FIND_OPS) {
      cpu_keys_lookup[find] = rand() % ((UINT32_MAX - 1) + 1) + 1;
      find++;
    }
  } // trace into array
  uint32_t bitmap_size = static_cast<uint32_t>(
      std::ceil(static_cast<double>(UINT32_MAX) / rangeSize));

  power_of_two = (uint32_t)std::log2(rangeSize);

#if defined(FSORT)
  float total_sorting_time = 0.0f;
  auto start_sort = HRClock::now();
#if defined(KEYSORT)
  std::sort(std::execution::par_unseq, cpu_kvs_insert,
            cpu_kvs_insert + NUM_ADD_OPS, compareByKey);
  std::sort(std::execution::par_unseq, cpu_keys_del, cpu_keys_del + NUM_REM_OPS,
            compareByKeyDS);
  std::sort(std::execution::par_unseq, cpu_keys_lookup,
            cpu_keys_lookup + NUM_FIND_OPS, compareByKeyDS);
#else
  std::sort(std::execution::par_unseq, cpu_kvs_insert,
            cpu_kvs_insert + NUM_ADD_OPS, compareByRange);
  std::sort(std::execution::par_unseq, cpu_keys_del, cpu_keys_del + NUM_REM_OPS,
            compareByRangeDS);
  std::sort(std::execution::par_unseq, cpu_keys_lookup,
            cpu_keys_lookup + NUM_FIND_OPS, compareByRangeDS);
#endif
  auto end_sort = HRClock::now();
  DurationFloatMS duration_sort = end_sort - start_sort;
  total_sorting_time += duration_sort.count();
#endif
  cout << " USE_TRACE_FILE: " << USE_TRACE_FILE
       << " Bitmap size: " << bitmap_size << " Range size: " << rangeSize
       << " GPU batch size: " << gpuBatchSize << "\n";

  // Cost across per-batch kernel launches
  float total_time = 0.0f;
  float total_insert_time = 0.0f;
  float total_delete_time = 0.0f;
  float total_search_time = 0.0f;

  // Cumulative cost of creating multiple batches
  float total_batch_time_insert = 0.0f;
  float total_batch_time_delete = 0.0f;
  float total_batch_time_search = 0.0f;
  float total_batch_time = 0.0f;

  /** Time across runs */
  float total_end_to_end_time = 0.0f;
  uint64_t gpu_outer_slot_size = getCapacity(bitmap_size);
  uint64_t inner_ht_slots = getCapacity(rangeSize);

  // printf("Outer slots: %lu and inner slots:%lu\n", gpu_outer_slot_size,
  //        inner_ht_slots);
  smallerPrimeCPU = 32;
#if defined(CG)
  smallerPrimeGPU = COOP_GROUP_SIZE;
  smallerPrimeInner = COOP_GROUP_SIZE;
#else
  smallerPrimeGPU = 32;
  smallerPrimeInner = 32;
#endif
  // Now, the hash table and arrays containing requested operations are ready.
  // We will start executing the operations and time them.

  for (uint32_t j = 0; j < runs; j++) {
    // Cost of per-batch kernels
    float per_iter_insert_time = 0.0f;
    float per_iter_delete_time = 0.0f;
    float per_iter_search_time = 0.0f;

    // Cost of creating a batch
    float per_iter_batch_time_insert = 0.0f;
    float per_iter_batch_time_delete = 0.0f;
    float per_iter_batch_time_search = 0.0f;

    auto *gpuHashTable =
        createGPUHash_UVM_CG(gpu_outer_slot_size, inner_ht_slots);
    // printGpuHashTable_CG(gpuHashTable, gpu_outer_slot_size, inner_ht_slots);

#if defined(OUTER_HASHTABLE_MEM_ADVISE_SA)
    cudaCheckErrorMacro(cudaMemAdvise(gpuHashTable,
                                      (gpu_outer_slot_size * sizeof(HoHGpu)),
                                      cudaMemAdviseSetAccessedBy, 0),
                        "Memadvise SetAccessedBy hint failure for hashtable");
#endif

#if defined(OUTER_HASHTABLE_MEM_ADVISE_SP)
    cudaCheckErrorMacro(cudaMemAdvise(gpuHashTable,
                                      (gpu_outer_slot_size * sizeof(HoHGpu)),
                                      cudaMemAdviseSetPreferredLocation, 0),
                        "Memadvise: SetPreferedLocation hint failed");
#endif

#if defined(OUTER_HASHTABLE_PREFETCH_HINT)
    cudaCheckErrorMacro(
        cudaMemPrefetchAsync(gpuHashTable,
                             (gpu_outer_slot_size * sizeof(HoHGpu)), 0),
        "Prefetching hint for the hash table failed");
#endif

    // The inner hash tables are allocated through separate memory allocation
    // hence require separate hints. However, it seems there is no benefit for
    // hints with the inner tables. In fact, there seems to be a slight
    // degradation.

#if defined(INNER_HASHTABLE_HINT_SA)
    for (uint64_t idx = 0; idx < gpu_outer_slot_size; idx++) {
      cudaCheckErrorMacro(cudaMemAdvise(gpuHashTable[idx].inner_hashtable,
                                        (innerHTSize * sizeof(KeyValue)),
                                        cudaMemAdviseSetAccessedBy, 0),
                          "Memadvise SetAccessedBy hint failure for hashtable");
    }
#endif

#if defined(INNER_HASHTABLE_PREFETCH)
    for (uint64_t idx = 0; idx < gpu_outer_slot_size; idx++) {
      cudaCheckErrorMacro(
          cudaMemPrefetchAsync(gpuHashTable[idx].inner_hashtable,
                               (innerHTSize * sizeof(KeyValue)), 0),
          "Prefetching hint of the hashtable failed");
    }
#endif

    auto start_main = HRClock::now();

    // UVM array for batched insertion on the GPU. The contents are copied in
    // batches from cpu_kvs_insert.
    KeyValue *gpu_uvm_insertion_batch = nullptr;
    cudaCheckErrorMacro(cudaMallocManaged(&gpu_uvm_insertion_batch,
                                          sizeof(KeyValue) * gpuBatchSize),
                        "[error] Failed to allocate GPU insertion list");

    // This will be required in future for migration but we can possibly #def it
    // away.
    uint32_t *uniqueCountList = nullptr;
    // cudaCheckErrorMacro(
    //     cudaMallocManaged(&uniqueCountList, sizeof(uint32_t) * 0),
    //     "Mem allocation failed for unique count list");

    // This is for stats.
    uint32_t *collision_list_outer = nullptr;
    // cudaCheckErrorMacro(
    //     cudaMallocManaged(&collision_list_outer, sizeof(uint32_t) * 0),
    //     "Mem allocation failed for the collision list outer");

    // FIXME: SB: Batch creation and kernel execution should be pipelined both
    // in HoH and UVM
    cout << "[info] Insert kernel starting\n";
    // Index tracker for the CPU array
    uint64_t cpu_counter = 0;
    // Total operations done across batches
    uint64_t sum_add_across_batches = 0;
    uint64_t num_batches = 0;

    // Iterate depending on the number of batched insertions required
#if defined(BSORT)
    static simple_cached_allocator<KeyValue> alloc;
#endif
    while (sum_add_across_batches < NUM_ADD_OPS) {
      // Per-batch counter
      uint64_t per_batch_gpu_ins = 0;

      auto start = HRClock::now();
      while (per_batch_gpu_ins < gpuBatchSize &&
             sum_add_across_batches < NUM_ADD_OPS) {
        gpu_uvm_insertion_batch[per_batch_gpu_ins].key =
            cpu_kvs_insert[cpu_counter].key;
        gpu_uvm_insertion_batch[per_batch_gpu_ins].value =
            cpu_kvs_insert[cpu_counter].value;
        per_batch_gpu_ins++;
        cpu_counter++;
        sum_add_across_batches++;
      }
      auto end = HRClock::now();

      DurationFloatMS duration = end - start;
      per_iter_batch_time_insert += duration.count();

      assert(per_batch_gpu_ins);

#if defined(UVM_MEM_ADVISE_SA)
      cudaCheckErrorMacro(
          cudaMemAdvise(gpu_uvm_insertion_batch,
                        (per_batch_gpu_ins * sizeof(KeyValue)),
                        cudaMemAdviseSetAccessedBy, 0),
          "Memadvise SetAccessedBy hint failure for insert array");
#endif
#if defined(UVM_PREFETCH_HINT)
      cudaCheckErrorMacro(
          cudaMemPrefetchAsync(gpu_uvm_insertion_batch,
                               (per_batch_gpu_ins * sizeof(KeyValue)), 0),
          "Prefetching hint of the insert array failed");
#endif
#if defined(BSORT)
      auto start_sort = HRClock::now();
#if defined(KEYSORT)
      thrust::sort(thrust::cuda::par(alloc), gpu_uvm_insertion_batch,
                   gpu_uvm_insertion_batch + per_batch_gpu_ins, CompareByKey());
#else
      thrust::sort(thrust::cuda::par(alloc), gpu_uvm_insertion_batch,
                   gpu_uvm_insertion_batch + per_batch_gpu_ins,
                   CompareByRangeShift(power_of_two));
#endif
      cudaDeviceSynchronize();
      auto end_sort = HRClock::now();
      DurationFloatMS duration_sort = end_sort - start_sort;
      printf("Sorting time %f\n", duration_sort.count());
      per_iter_insert_time += duration_sort.count();
#endif
#if defined(CG)
      per_iter_insert_time += batch_insert_gpu_unique_count_CG(
          gpuHashTable, gpu_uvm_insertion_batch, per_batch_gpu_ins,
          gpu_outer_slot_size, inner_ht_slots, rangeSize);
#else
      per_iter_insert_time += batch_insert_gpu_unique_count(
          gpuHashTable, gpu_uvm_insertion_batch, per_batch_gpu_ins,
          gpu_outer_slot_size, inner_ht_slots, rangeSize);
#endif
      num_batches++;
      cout << "Batch " << num_batches << " completed with " << per_batch_gpu_ins
           << " inserts\n";
    }
    // The physical pages should be freed.
    cudaCheckErrorMacro(cudaFree(gpu_uvm_insertion_batch),
                        "Failed to free insertion list");
    if (collision_list_outer) {
      cudaCheckErrorMacro(cudaFree(collision_list_outer),
                          "Failed to free collision list");
    }
    if (uniqueCountList) {
      cudaCheckErrorMacro(cudaFree(uniqueCountList),
                          "Failed to free unqiue count list");
    }

    uint32_t *gpu_uvm_deletion_batch = nullptr;
    bool *delete_result = nullptr;
    if (NUM_REM_OPS) {
      cudaCheckErrorMacro(cudaMallocManaged(&gpu_uvm_deletion_batch,
                                            sizeof(uint32_t) * gpuBatchSize),
                          "[error] Failed to allocate gpu deletion list");
      cudaCheckErrorMacro(
          cudaMallocManaged(&delete_result, sizeof(bool) * gpuBatchSize),
          "[error] Failed to allocate memory for delete results");

      // We do not need a memset on delete_result because all the array indices
      // are overwritten irrespective of whether the delete succeeds or fails.

      cout << "[info] Delete kernel starting\n";

      cpu_counter = 0;
      num_batches = 0;
      uint64_t sum_del_across_batches = 0;
      // #if defined(BSORT)
      //       static simple_cached_allocator<KeyValue> alloc;
      // #endif
      while (sum_del_across_batches < NUM_REM_OPS) {
        // Per-batch counter
        uint64_t per_batch_gpu_del = 0;

        auto start = HRClock::now();
        while (per_batch_gpu_del < gpuBatchSize &&
               sum_del_across_batches < NUM_REM_OPS) {
          gpu_uvm_deletion_batch[per_batch_gpu_del] = cpu_keys_del[cpu_counter];
          per_batch_gpu_del++;
          cpu_counter++;
          sum_del_across_batches++;
        }
        auto end = HRClock::now();

        DurationFloatMS duration = end - start;
        per_iter_batch_time_delete += duration.count();

        assert(per_batch_gpu_del);

#if defined(UVM_MEM_ADVISE_SA)
        cudaCheckErrorMacro(
            cudaMemAdvise(gpu_uvm_deletion_batch,
                          (per_batch_gpu_del * sizeof(uint32_t)),
                          cudaMemAdviseSetAccessedBy, 0),
            "Memadvise SetAccessedBy hint failure for delete array");
        cudaCheckErrorMacro(
            cudaMemAdvise(delete_result, (per_batch_gpu_del * sizeof(bool)),
                          cudaMemAdviseSetAccessedBy, 0),
            "Memadvise SetAccessedBy hint failure for delete status");
#endif

#if defined(UVM_PREFETCH_HINT)
        cudaCheckErrorMacro(
            cudaMemPrefetchAsync(gpu_uvm_deletion_batch,
                                 (per_batch_gpu_del * sizeof(uint32_t)), 0),
            "Prefetching hint of the delete array failed");
        cudaCheckErrorMacro(
            cudaMemPrefetchAsync(delete_result,
                                 (per_batch_gpu_del * sizeof(bool)), 0),
            "Prefetching hint of the delete status failed");
#endif
#if defined(BSORT)
        auto start_sort = HRClock::now();
#if defined(KEYSORT)
        thrust::sort(thrust::cuda::par(alloc), gpu_uvm_deletion_batch,
                     gpu_uvm_deletion_batch + per_batch_gpu_del,
                     CompareByKey());
#else
        thrust::sort(thrust::cuda::par(alloc), gpu_uvm_deletion_batch,
                     gpu_uvm_deletion_batch + per_batch_gpu_del,
                     CompareByRangeShiftDS(power_of_two));
#endif
        cudaDeviceSynchronize();
        auto end_sort = HRClock::now();
        DurationFloatMS duration_sort = end_sort - start_sort;
        printf("Sorting time %f\n", duration_sort.count());
        per_iter_delete_time += duration_sort.count();
#endif
#if defined(CG)
        per_iter_delete_time += batch_delete_gpu_unique_count_CG(
            gpuHashTable, gpu_uvm_deletion_batch, per_batch_gpu_del,
            gpu_outer_slot_size, inner_ht_slots, rangeSize, delete_result);
#else

        per_iter_delete_time += batch_delete_gpu_unique_count(
            gpuHashTable, gpu_uvm_deletion_batch, per_batch_gpu_del,
            gpu_outer_slot_size, inner_ht_slots, rangeSize, delete_result);
#endif
        num_batches++;
        cout << "Batch " << num_batches << " completed with "
             << per_batch_gpu_del << " deletions\n";
      }

      // The physical pages should be freed.
      cudaCheckErrorMacro(cudaFree(gpu_uvm_deletion_batch),
                          "Failed to free deletion list");
      cudaCheckErrorMacro(cudaFree(delete_result),
                          "Failed to free up delete status list");
    }

    uint32_t *gpu_uvm_search_batch = nullptr;
    uint32_t *searched_results = nullptr;
    if (NUM_FIND_OPS) {
      cudaCheckErrorMacro(cudaMallocManaged(&gpu_uvm_search_batch,
                                            sizeof(uint32_t) * gpuBatchSize),
                          "[error] Failed to allocate GPU search list");
      cudaCheckErrorMacro(
          cudaMallocManaged(&searched_results, sizeof(uint32_t) * gpuBatchSize),
          "[error] Failed to allocate GPU search results");

      // We do not need a memset because the driver will initialize the pages to
      // zero. We can identify which searches failed (\ie, keys are not there)
      // by checking which values are zero.

      cout << "[info] Search kernel starting\n";

      cpu_counter = 0;
      num_batches = 0;
      uint64_t sum_find_across_batches = 0;
      while (sum_find_across_batches < NUM_FIND_OPS) {
        // Per-batch counter
        uint64_t per_batch_gpu_find = 0;

        auto start = HRClock::now();
        while (per_batch_gpu_find < gpuBatchSize &&
               sum_find_across_batches < NUM_FIND_OPS) {
          gpu_uvm_search_batch[per_batch_gpu_find] =
              cpu_keys_lookup[cpu_counter];
          per_batch_gpu_find++;
          cpu_counter++;
          sum_find_across_batches++;
        }
        auto end = HRClock::now();

        DurationFloatMS duration = end - start;
        per_iter_batch_time_search += duration.count();

        assert(per_batch_gpu_find);

#if defined(UVM_MEM_ADVISE_SA)
        cudaCheckErrorMacro(
            cudaMemAdvise(gpu_uvm_search_batch,
                          (per_batch_gpu_find * sizeof(uint32_t)),
                          cudaMemAdviseSetAccessedBy, 0),
            "Memadvise SetAccessedBy hint failure for search array");
        cudaCheckErrorMacro(
            cudaMemAdvise(searched_results,
                          (per_batch_gpu_find * sizeof(uint32_t)),
                          cudaMemAdviseSetAccessedBy, 0),
            "Memadvise SetAccessedBy hint failure for delete status");
#endif

#if defined(UVM_PREFETCH_HINT)
        cudaCheckErrorMacro(
            cudaMemPrefetchAsync(gpu_uvm_search_batch,
                                 (per_batch_gpu_find * sizeof(uint32_t)), 0),
            "Prefetching hint of the search array failed");
        cudaCheckErrorMacro(
            cudaMemPrefetchAsync(searched_results,
                                 (per_batch_gpu_find * sizeof(uint32_t)), 0),
            "Prefetching hint of the delete status failed");
#endif
#if defined(BSORT)
        auto start_sort = HRClock::now();
#if defined(KEYSORT)
        thrust::sort(thrust::cuda::par(alloc), gpu_uvm_search_batch,
                     gpu_uvm_search_batch + per_batch_gpu_find, CompareByKey());
#else
        thrust::sort(thrust::cuda::par(alloc), gpu_uvm_search_batch,
                     gpu_uvm_search_batch + per_batch_gpu_find,
                     CompareByRangeShiftDS(power_of_two));
#endif
        cudaDeviceSynchronize();
        auto end_sort = HRClock::now();
        DurationFloatMS duration_sort = end_sort - start_sort;
        printf("Sorting time %f\n", duration_sort.count());
        per_iter_search_time += duration_sort.count();
#endif
#if defined(CG)
        per_iter_search_time += batch_search_gpu_unique_count_CG(
            gpuHashTable, gpu_uvm_search_batch, per_batch_gpu_find,
            gpu_outer_slot_size, inner_ht_slots, rangeSize, searched_results);
#else
        per_iter_search_time += batch_search_gpu_unique_count(
            gpuHashTable, gpu_uvm_search_batch, per_batch_gpu_find,
            gpu_outer_slot_size, inner_ht_slots, rangeSize, searched_results);
#endif
        num_batches++;
        cout << "Batch " << num_batches << " completed with "
             << per_batch_gpu_find << " searches\n";
      }
    }
#if defined(BSORT)
    alloc.reset();
#endif
    auto end_main = HRClock::now();
    DurationFloatMS end_to_end_duration = end_main - start_main;
    total_end_to_end_time += end_to_end_duration.count();

    if (runs > 1) { // Save cost if there are no more runs
      cudaCheckErrorMacro(cudaFree(gpu_uvm_search_batch),
                          "Failed to free search list");
      cudaCheckErrorMacro(cudaFree(searched_results),
                          "Failed to free search list");
    }

#ifdef KEY_CHECK
    KeyCheckGPUHoH(gpuHashTable, gpu_outer_slot_size, cpu_kvs_insert,
                   NUM_ADD_OPS);
#endif
#ifdef PRINT
    printGpuHashTable_CG(gpuHashTable, gpu_outer_slot_size, inner_ht_slots);
#endif

    total_insert_time += per_iter_insert_time;
    total_delete_time += per_iter_delete_time;
    total_search_time += per_iter_search_time;
    total_time +=
        (per_iter_insert_time + per_iter_delete_time + per_iter_search_time);

    total_batch_time_insert += per_iter_batch_time_insert;
    total_batch_time_delete += per_iter_batch_time_delete;
    total_batch_time_search += per_iter_batch_time_search;
    total_batch_time +=
        (per_iter_batch_time_insert + per_iter_batch_time_delete +
         per_iter_batch_time_search);
    for (uint32_t i = 0; i < gpu_outer_slot_size; i++) {
      cudaCheckErrorMacro(cudaFree(gpuHashTable[i].inner_hashtable),
                          "Failed to free GPU inner hash tables");
    }
    cudaCheckErrorMacro(cudaFree(gpuHashTable),
                        "Failed to free GPU hash table");
  }

#if defined(FSORT)
  cout << "Total time taken by sorting of full input (ms): "
       << total_sorting_time << "\n";
#endif
#if defined(BSORT)
  cout << "Total time taken by insert kernel(including sort) (ms): "
       << (total_insert_time / runs) << "\n";
#else
  cout << "Total time taken by insert kernel (ms): "
       << (total_insert_time / runs) << "\n";
#endif
  cout << "Total time required by insert batch creation (ms): "
       << (total_batch_time_insert / runs) << "\n";
#if defined(BSORT)
  cout << "Total time taken by delete kernel including sort (ms): "
       << (total_delete_time / runs) << "\n";
#else
  cout << "Total time taken by delete kernel (ms): "
       << (total_delete_time / runs) << "\n";
#endif
  cout << "Total time required by delete batch creation (ms): "
       << (total_batch_time_delete / runs) << "\n";
#if defined(BSORT)
  cout << "Total time taken by search kernel including sort (ms): "
       << (total_search_time / runs) << "\n";
#else
  cout << "Total time taken by search kernel (ms): "
       << (total_search_time / runs) << "\n";
#endif
  cout << "Total time required by search batch creation (ms): "
       << (total_batch_time_search / runs)
       << "\nTotal time taken by UVM hash table implementation (ms): "
       << (total_time / runs)
       << "\nTotal time required by overall batch creation (ms): "
       << (total_batch_time / runs) << "\nTotal per-run end-to-end time (ms): "
       << (total_end_to_end_time / runs) << "\n\n";

  return EXIT_SUCCESS;
}
