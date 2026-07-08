#include <array>
#include <random>
#include <set>
#include <vector>

// #define REFINEMENT_PHASE_OFF

#include "GPHOS.cuh"
#include "GPHOS_inner.cuh"
#include "workspace.cuh"

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                   virtual_bucket_n>::validateSettings() {
#ifdef CROSS_SM_INDEX
#ifdef ONE_SUBTABLE_PER_SM
  panic("Invalid settings.");
#endif
#ifdef CELL_SPLIT_ENABLED
  panic("Invalid settings.");
#endif
#ifdef L2_AS_FAST_MEMORY
  panic("Invalid settings.");
#endif
  // if (_cells_length % BLOCK_COUNT != 0) {
  //   vclog(INFO, "{} % {} != 0", _cells_length, BLOCK_COUNT);
  // }
  // assert(_cells_length % BLOCK_COUNT == 0);
#endif

#ifdef CUCKOO_VIRTUAL_BUCKETS
  panic("Not implemented.")
#endif

#ifdef ONE_SUBTABLE_PER_SM
      panic("Not implemented.");
#endif

  vclog(INFO, "GPU_INFO:\tShared memory per block detected is {} bytes",
        getSharedMemoryPerBlockSizeInBytes());
  vclog(INFO, "GPU_INFO:\t# of MultiStreaming Processors is {}",
        getMultiProcessorCount());
  vclog(INFO, "GPU_INFO:\tTotal shared memory is {} kB",
        getMultiProcessorCount() * getSharedMemoryPerBlockSizeInBytes() /
            1024.0);
  vclog(INFO, "GPU_INFO:\t# of max threads per block is {}",
        getMaxThreadsPerBlock());
  vclog(INFO,
        "TABLE_INFO:\tShared memory used per block in lookup kernel is {}",
        SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE);
  vclog(INFO, "TABLE_INFO:\tBlock count is {}", BLOCK_COUNT);
  vclog(INFO, "TABLE_INFO:\tTotal shared memory used in lookup kernel is {} kB",
        _cells_length * sizeof(CELL_T) / 1024.0);
  vclog(INFO,
        "TABLE_INFO:\tShared memory used per block in lookup kernel is {} kB",
        _cells_length * sizeof(CELL_T) / (1024.0 * BLOCK_COUNT));
  bool iplv_on;
#ifdef DISABLE_VECTORIZATION_AND_INSTRUCTION_PARALLEL
  iplv_on = false;
#else
  iplv_on = true;
#endif
  vclog(INFO, "TABLE_INFO:\tIPL&V Optimization: {}", iplv_on);
  bool nkpr_on;
#ifndef NKPR
  nkpr_on = false;
#else
  nkpr_on = true;
#endif
  vclog(INFO, "TABLE_INFO:\tNKPR Optimization: {}", nkpr_on);

  if (SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE >
      getSharedMemoryPerBlockSizeInBytes()) {
    panic("SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE > "
          "getSharedMemoryPerBlockSizeInBytes({} bytes)",
          getSharedMemoryPerBlockSizeInBytes());
  }

#if defined NO_BLOCK_LIMIT_CSI && !defined CROSS_SM_INDEX
  panic("NO_BLOCK_LIMIT_CSI must be used with CROSS_SM_INDEX");
#endif

#ifndef CROSS_SM_INDEX
  if (_cells_length * sizeof(CELL_T) > getAvailableFastMemorySizeInBytes()) {
    panic("Cell length is larger than the maximum fast memory size, cell "
          "size: "
          "{} bytes, shared memory size: {} bytes, L2 setaside size: {} "
          "bytes.",
          _cells_length * sizeof(CELL_T), getSharedMemoryPerBlockSizeInBytes(),
          getL2MaxPersistenceSizeInBytes());
  }
#else
#ifndef NO_BLOCK_LIMIT_CSI
  if (_cells_length * sizeof(CELL_T) >
      getAvailableFastMemorySizeInBytes() * BLOCK_COUNT) {
    panic("Cell length is larger than the maximum fast memory size, cell "
          "size: "
          "{} bytes, shared memory size: {} bytes, L2 setaside size: {} "
          "bytes.",
          _cells_length * sizeof(CELL_T), getSharedMemoryPerBlockSizeInBytes(),
          getL2MaxPersistenceSizeInBytes());
  }
#endif
#endif

  if (virtual_bucket_n < 2) {
    panic("virtual bucket n needs to be larger than 1.");
  }
  if (USED_CELLS_ARRAY_LENGTH(_cells_length) < 2) {
    panic("Too small cells_length.");
  }
  if (sizeof(CELL_T) <= 4 && virtual_bucket_n > (1LL << (sizeof(CELL_T) * 8))) {
    panic("virtual_bucket_n is too large that the current cell value cannot "
          "represent.");
  }
  int expected_unused_bucket =
      (int)(_bucket_n *
            (std::pow((_bucket_n - virtual_bucket_n) / (1.0 * _bucket_n),
                      USED_CELLS_ARRAY_LENGTH(_cells_length))));
  if (expected_unused_bucket / (1.0 * _bucket_n) >= 0.1) {
    vclog(DEBUG, "Expected empty buckets are {} in {}", expected_unused_bucket,
          _bucket_n);
    vclog(WARN,
          "expected_unused_bucket / (1.0 * _bucket_n) should better be "
          "smaller "
          "than 0.1, otherwise too many buckets are unused. Current expected "
          "unused bucket is {} in {} buckets",
          expected_unused_bucket, _bucket_n);
  }

  if (!checkAllBitsSet(_data[0])) {
    panic("Bug exists! Data array are not initialized correctly.");
  }
  printf("CVBID Conflict Resolving...standby...\n");

  std::set<int> counter;
  for (int ci = 0; ci < USED_CELLS_ARRAY_LENGTH(_cells_length); ci++) {
    CELL_T cvbid = 0;
    unsigned long long int cell_value = 0;
    // printf("Cells length: %u\n",_cells_length);
    while (cell_value <= std::numeric_limits<CELL_T>::max()) {
      counter.clear();
      bool conflict = false;
      for (int bs = 0; bs < virtual_bucket_n; bs++) {
        int bucket_id = HASH_BUCKET_ID(ci, bs, virtual_bucket_n,
                                       USED_CELLS_ARRAY_LENGTH(_cells_length),
                                       cvbid, _bucket_n, _rand_seed);
        if (counter.count(bucket_id) > 0) {
          // debug area
          // vclog(INFO, "CELL {} CVBID {} VB {} conflict because BKTID {} already used", ci, cvbid, bs, bucket_id);
          // // for (int dbs = 0; dbs < virtual_bucket_n; dbs++) {
          // //   // printf("%d ",HASH_BUCKET_ID(ci, dbs, virtual_bucket_n,
          // //   //   USED_CELLS_ARRAY_LENGTH(_cells_length), cvbid,
          // //   //   _bucket_n, _rand_seed));
          // // }
          // printf("\n");
          // delete above

          conflict = true;
          break;
        }
        counter.insert(bucket_id);
      }
      // printf("For loop completed\n");
      if (conflict) {
        ++cvbid;
        cell_value = (unsigned long long int)GET_CELL_K_FROM_OFFSET_CVBID(
            0, cvbid, virtual_bucket_n);
      } else {
        break;
      }
    }
    if (cell_value > std::numeric_limits<CELL_T>::max()) {
      panic("Cannot get start, there is a bucket always with conflict in "
            "virtual buckets that cannot be resolved by changing cvbid.");
    }
    if (cvbid > 0) {
      _cells[ci] = GET_CELL_K_FROM_OFFSET_CVBID(0, cvbid, virtual_bucket_n);
    }
  }
  printf("CVBID Conflict Resolve Complete.\n");
}

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<
    T, bucket_cap, lookup_group_size, insert_group_size,
    virtual_bucket_n>::initialize_exp_members(json::value *_exp_object,
                                              Time_recorder *_time_recorder) {
  exp_object = _exp_object;
  time_recorder = _time_recorder;
}

template <typename T>
void finalize_CSI(T *results, T *csi_results, size_t *csi_block_ptrs,
                  size_t *vals_loc, const int n) {
  for (int i = 0; i < n; i++) {
    results[i] = csi_results[vals_loc[i]];
    // vclog(DEBUG, "result[{}] = csi_results[{}]", i, vals_loc[i]);
  }
}

// TODO, remember to initialize the locks
// TODO, make bucket_cap and group_size to be template constant
template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                   virtual_bucket_n>::insert_vals(const T *const vals,
                                                  const int n,
                                                  UnifiedTimeRecorder
                                                      *recorder) {
  // panic("Not implemented.");
  vclog(INFO, "Entering insert kernel...");

#ifdef CELL_SPLIT_ENABLED
  panic("GPU insert does not support cell split now.");
#endif

#ifdef CUCKOO_VIRTUAL_BUCKETS
  panic("Cuckoo virtual buckets has not been implemented yet.");
#endif
  // Allocate GPU memory space.
  T *d_vals;
  T *d_data;
  CELL_T *d_cells;

  LOCK_T *d_bucket_locks;
  // LOCK_T *d_cell_read_counter;
  // LOCK_T *d_cell_read_locks;
  // LOCK_T *d_cell_global_locks;

  bool *h_insert_result = new bool[n];
  bool *d_insert_result;
  cudaMalloc((void **)&d_insert_result, n * sizeof(bool));

  cudaMalloc((void **)&d_vals, n * sizeof(T));
  cudaMalloc((void **)&d_data, _bucket_n * bucket_cap * sizeof(T));
  cudaMalloc((void **)&d_cells,
             (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(CELL_T));

  cudaMalloc((void **)&d_bucket_locks, _bucket_n * sizeof(LOCK_T));
  // cudaMalloc((void **)&d_cell_read_counter,
  //            (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(LOCK_T));
  // cudaMalloc((void **)&d_cell_read_locks,
  //            (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(LOCK_T));
  // cudaMalloc((void **)&d_cell_global_locks,
  //            (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(LOCK_T));

  cudaMemcpy(d_vals, vals, n * sizeof(T), cudaMemcpyHostToDevice);
  cudaMemcpy(d_data, _data, _bucket_n * bucket_cap * sizeof(T),
             cudaMemcpyHostToDevice);
  cudaMemcpy(d_cells, _cells,
             (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(CELL_T),
             cudaMemcpyHostToDevice);

  cudaMemset(d_bucket_locks, 0, _bucket_n * sizeof(LOCK_T));
  // cudaMemset(d_cell_read_counter, 0,
  //            (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(LOCK_T));
  // cudaMemset(d_cell_read_locks, 0,
  //            (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(LOCK_T));
  // cudaMemset(d_cell_global_locks, 0,
  //            (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(LOCK_T));

  if (recorder) {
    recorder->start_timer("insert_kernel", true);
  }

  // lauch kernel
  // GPHOSGPUTableInsertValsKernel<T, bucket_cap, insert_group_size,
  //                                  virtual_bucket_n>
  //     <<<BLOCK_COUNT, GPHOS_BLOCK_SIZE>>>(
  //         d_vals, n, d_bucket_locks, d_cell_read_counter, d_cell_read_locks,
  //         d_cell_global_locks, d_data, _bucket_n, d_cells, _cells_length,
  //         _rand_seed, false, true, false, ONLY_DIRECT_INSERT);
  bool dont_insert_already_succeed = false;
  int write_back_insert_result = 0;
  bool allow_complex_insert = false;

  if (write_back_insert_result == 1) {
    cudaMemset(d_insert_result, true, n * sizeof(bool));
  } else if (write_back_insert_result == 2) {
    cudaMemset(d_insert_result, false, n * sizeof(bool));
  }

  int insert_block_count = (int)ceil(n / GPHOS_BLOCK_SIZE);
  vclog(INFO, "Calling insert kernel...");
  panic("not supported");
  // simplifiedGPHOSGPUTableInsertValsKernel<T, bucket_cap, insert_group_size, virtual_bucket_n>
  //     <<<insert_block_count, GPHOS_BLOCK_SIZE>>>(
  //     d_vals, n,
  //     d_bucket_locks,
  //     d_data, _bucket_n,
  //     d_cells, _cells_length, _rand_seed,
  //     d_insert_result,
  //     dont_insert_already_succeed, // if true, then read insert result and only insert false ones.
  //     write_back_insert_result, // 0 for not write back, 1 for write false for failed, 2 for write true for succeed.
  //     allow_complex_insert);

  cudaError_t cudaerr = cudaDeviceSynchronize();
  gpuErrchk(cudaerr);

  vclog(INFO, "Insert kernel complete...");

  if (recorder) {
    recorder->finish_timer("insert_kernel");
  }

  // Copy back and Free
  cudaMemcpy(_data, d_data, _bucket_n * bucket_cap * sizeof(T),
             cudaMemcpyDeviceToHost);
  cudaMemcpy(_cells, d_cells,
             (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(CELL_T),
             cudaMemcpyDeviceToHost);
  if (write_back_insert_result != 0) {
    cudaMemcpy(h_insert_result, d_insert_result, n * sizeof(bool),
               cudaMemcpyDeviceToHost);
  }

  cudaFree(d_vals);
  cudaFree(d_data);
  cudaFree(d_cells);
  cudaFree(d_bucket_locks);
  cudaFree(d_insert_result);

  delete[] h_insert_result;
  // cudaFree(d_cell_read_counter);
  // cudaFree(d_cell_read_locks);
  // cudaFree(d_cell_global_locks);
}

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                   virtual_bucket_n>::
    insert_key_values(const T *const kv_array, // T is kv compacted type
                      const int n, UnifiedTimeRecorder *recorder) {
  cudaSetDevice(0);
  vclog(INFO, "Entering insert kernel...");
// printf("Value of n: %d\n", n);
#ifdef OUTPUT_INSERT_RESULT_COUNT
  int dionlyphase_success = 0;
  int dionlyphase_failed = 0;
  int rphase_success = 0;
  int rphase_failed = 0;
  printf("Value of n: %d\n", n);
  bool *middle_insert_result = new bool[n];

#endif

#ifdef CELL_SPLIT_ENABLED
  panic("GPU insert does not support cell split now.");
#endif

  // Allocate GPU memory space.
  T *vals = (T *)kv_array;

  LOCK_T *bucket_locks;
  LOCK_T *cell_locks;
  LOCK_T *group_rank_counter;

  bool *insert_result;
  printf("Value of n: %d\n", n);
  cudaMallocManaged(&insert_result, sizeof(bool) * n);
  cudaMallocManaged((void **)&bucket_locks, _bucket_n * sizeof(LOCK_T));
  cudaMallocManaged((void **)&cell_locks,
                    (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) *
                        sizeof(LOCK_T));
  cudaMallocManaged((void **)&group_rank_counter, sizeof(LOCK_T));

  cudaMemAdvise(insert_result, (n * sizeof(bool)), cudaMemAdviseSetAccessedBy,
                0);
  cudaMemPrefetchAsync(insert_result, (n * sizeof(bool)), 0);

  cudaMemAdvise(bucket_locks, (_bucket_n * sizeof(LOCK_T)),
                cudaMemAdviseSetAccessedBy, 0);
  cudaMemPrefetchAsync(bucket_locks, (_bucket_n * sizeof(LOCK_T)), 0);

  cudaMemAdvise(cell_locks,
                (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length) * sizeof(LOCK_T)),
                cudaMemAdviseSetAccessedBy, 0);
  cudaMemPrefetchAsync(
      cell_locks, (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length) * sizeof(LOCK_T)),
      0);

  cudaMemAdvise(group_rank_counter, (sizeof(LOCK_T)),
                cudaMemAdviseSetAccessedBy, 0);
  cudaMemPrefetchAsync(group_rank_counter, (sizeof(LOCK_T)), 0);

  // cudaMemcpy(d_vals, kv_array, n * sizeof(T), cudaMemcpyHostToDevice);

  // cudaMemset(d_bucket_locks, 0, _bucket_n * sizeof(LOCK_T));
  // cudaMemset(d_cell_locks, 0,
  //            (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(LOCK_T));
  // cudaMemset(d_group_rank_counter, 0, sizeof(LOCK_T));
  cudaMemset(insert_result, true, n * sizeof(bool));

  int insert_block_count = (int)ceil(n * 1.0 / GPHOS_BLOCK_SIZE);
  vclog(INFO, "Calling insert kernel with grid {} block {}...",
        insert_block_count, GPHOS_BLOCK_SIZE);

  if (recorder) {
    recorder->start_timer("insert_kernel", true);
  }

  if (recorder) {
    recorder->start_timer("insert_kernel_fill_phase", true);
  }

  DIOnlyInsertKeyValueKernel<T, bucket_cap, insert_group_size, virtual_bucket_n>
      <<<insert_block_count, GPHOS_BLOCK_SIZE>>>(
          vals, n, bucket_locks, _data, _bucket_n, _cells, _cells_length,
          _rand_seed, insert_result);
  cudaError_t cudaerr = cudaDeviceSynchronize();
  gpuErrchk(cudaerr);

  if (recorder) {
    recorder->finish_timer("insert_kernel_fill_phase");
  }
  if (recorder) {
    recorder->finish_timer("insert_kernel");
  }

#ifdef OUTPUT_INSERT_RESULT_COUNT
  cudaMemcpy(middle_insert_result, insert_result, n * sizeof(bool),
             cudaMemcpyDeviceToHost);
  for (int i = 0; i < n; i++) {
    if (middle_insert_result[i] == false)
      dionlyphase_failed += 1;
    else
      dionlyphase_success += 1;
  }
  cudaerr = cudaDeviceSynchronize();
  gpuErrchk(cudaerr);
#endif

  vclog(INFO, "Insert kernel Saturation Fill Phase Complete...");

  if (recorder) {
    recorder->restart_timer("insert_kernel");
  }
  if (recorder) {
    recorder->start_timer("insert_kernel_refine_phase", true);
  }
  size_t total_workspaces_size = get_maximum_shared_memory_per_block();

  size_t nb = get_GPU_SM_count();
  size_t nt = 128;
  size_t ss = total_workspaces_size;
  vclog(INFO,
        "Calling RemainingPhaseInsertKeyValueKernel with {} blocks, {} threads "
        "per block, {} bytes shared memory per block",
        nb, nt, ss);
  vclog(INFO,
        "{} bytes per workspace, {} workspaces per block, {} insert groups per "
        "blocks",
        WORKSPACE_SIZE, TOTAL_WORKSPACES_NUMBER(total_workspaces_size),
        nt / insert_group_size);
  if (TOTAL_WORKSPACES_NUMBER(total_workspaces_size) < nt / insert_group_size) {
    vclog(INFO,
          "It seems there is still a bug in the shared workspace lock scheme. "
          "Please make sure the workspace per block is larger than group per "
          "block temporarily.",
          WORKSPACE_SIZE, TOTAL_WORKSPACES_NUMBER(total_workspaces_size),
          nt / insert_group_size);
    assert(TOTAL_WORKSPACES_NUMBER(total_workspaces_size) >=
           nt / insert_group_size);
  }

#ifndef REFINEMENT_PHASE_OFF
  cudaFuncSetAttribute(
      RemainingPhaseInsertKeyValueKernel<T, bucket_cap, insert_group_size,
                                         virtual_bucket_n>,
      cudaFuncAttributeMaxDynamicSharedMemorySize, ss);
  RemainingPhaseInsertKeyValueKernel<T, bucket_cap, insert_group_size,
                                     virtual_bucket_n>
      <<<nb, nt, ss>>>(vals, n, bucket_locks, cell_locks, group_rank_counter,
                       total_workspaces_size, _data, _bucket_n, _cells,
                       _cells_length, _rand_seed, insert_result);
  cudaerr = cudaDeviceSynchronize();
  gpuErrchk(cudaerr);
#endif

  if (recorder) {
    recorder->finish_timer("insert_kernel_refine_phase");
  }

  vclog(INFO, "Insert kernel Refinement Phase complete...");

  if (recorder) {
    recorder->finish_timer("insert_kernel");
  }

  // Copy back and Free
  // cudaMemcpy(_data, d_data, _bucket_n * bucket_cap * sizeof(T),
  //            cudaMemcpyDeviceToHost);
  // cudaMemcpy(_cells, d_cells,
  //            (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(CELL_T),
  //            cudaMemcpyDeviceToHost);
  // cudaMemcpy(h_insert_result, d_insert_result, n * sizeof(bool),
  //            cudaMemcpyDeviceToHost);

#ifdef OUTPUT_INSERT_RESULT_COUNT
  // printf("Refine ");
  for (int i = 0; i < n; i++) {
    if (insert_result[i] == false)
      rphase_failed += 1;
    else if (insert_result[i] == true && middle_insert_result[i] == false) {
      rphase_success += 1;
    }
  }
  // printf("\n");
  // printf("Discard ");
  // for (int i = 0; i < n; i++) {
  //   if (h_insert_result[i] == false) printf("%d ", i);
  // }
  // printf("\n");
  fmt::print("FILL_SUC {}\tFILL_FAILED {}\nRefine_SUC {}\tRefine_FAILED {}\n",
             dionlyphase_success, dionlyphase_failed, rphase_success,
             rphase_failed);
#endif

  cudaFree(bucket_locks);
  cudaFree(insert_result);
  cudaFree(cell_locks);
  cudaFree(group_rank_counter);

  cudaFree(insert_result);
  delete[] middle_insert_result;
}

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                   virtual_bucket_n>::insert_vals_CPU(const T *const vals,
                                                      const int n,
                                                      const int fail_limit) {
  // GPHOSGPUTableInsertValsCPU<T, bucket_cap, insert_group_size,
  //                               virtual_bucket_n>(
  //     vals, n, &_size, _data, _bucket_n, _cells, _cells_length, _rand_seed,
  //     fail_limit);
}

// Note:
template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
__host__ int cellSplit(T key, int cellId, T *const data, int *data_size,
                       const int bucket_n, CELL_T *cells, const int cell_length,
                       const int rand_seed, T *reinsert_buffer_cqueue,
                       int *reinsert_buffer_cqueue_front,
                       int *reinsert_buffer_cqueue_rear,
                       const int reinsert_buffer_cqueue_size) {
  // if (CQ_IS_FULL(reinsert_buffer_cqueue, *reinsert_buffer_cqueue_front,
  //                *reinsert_buffer_cqueue_rear, reinsert_buffer_cqueue_size))
  // {
  //   vclog(
  //       WARN,
  //       "Cell split fails, the reinsert buffer is not large enough to put "
  //       "all elements need to be inserted.");
  //   return -1;
  // }
  // else
  // {
  //   CQ_PUSH(reinsert_buffer_cqueue, *reinsert_buffer_cqueue_front,
  //           *reinsert_buffer_cqueue_rear, reinsert_buffer_cqueue_size, key);
  // }

  // CELL_T offset = CELL_AT_I(cells, cellId);

  // for (int vbi = 0; vbi < virtual_bucket_n; vbi++)
  // {
  //   int bucketId = HASH_BUCKET_ID(cellId, vbi, virtual_bucket_n,
  //                                 USED_CELLS_ARRAY_LENGTH(cell_length),
  //                                 bucket_n, rand_seed);
  //   for (int ei = 0; ei < bucket_cap; ei++)
  //   {
  //     T *elem = &BUCKET_I_ELEMENT_J(data, bucketId, ei, bucket_cap);
  //     if (!checkAllBitsSet(*elem))
  //     {
  //       int elem_cellId = HASH_CELL_ID(
  //           *elem, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
  //       if (cellId == elem_cellId)
  //       {
  //         int elem_bs = HASH_BUCKET_S(*elem, rand_seed, offset,
  //                                     virtual_bucket_n);
  //         if (elem_bs == vbi)
  //         {
  //           if (CQ_IS_FULL(reinsert_buffer_cqueue,
  //                          *reinsert_buffer_cqueue_front,
  //                          *reinsert_buffer_cqueue_rear,
  //                          reinsert_buffer_cqueue_size))
  //           {
  //             vclog(WARN,
  //                   "Cell split fails, the reinsert buffer is "
  //                   "not large enough "
  //                   "to put all elements need to be inserted.");
  //             return -1;
  //           }
  //           else
  //           {
  //             CQ_PUSH(reinsert_buffer_cqueue,
  //                     *reinsert_buffer_cqueue_front,
  //                     *reinsert_buffer_cqueue_rear,
  //                     reinsert_buffer_cqueue_size, *elem);
  //           }

  //           *elem = getAllBitsSet<T>();
  //           *data_size -= 1;
  //         }
  //       }
  //     }
  //   }
  // }

  // CELL_AT_I(cells, cellId) = virtual_bucket_n;
  // return 0;
}

// Note:
/*
 circular move should be triggered when key is trying to insert into a full
 bucket. return the change of size return 1 if the key is sucessfully inserted,
 return 0 if circular move fails (or cell split should start). If CELL_SPLIT is
 enabled, cell split should start when circular move fails, in that case,
 reinsert_n keys that needs to be reinserted is deleted from the buckets, and
 put into the reinsert_buffer_cqueue. if reinsert_buffer_cqueue is full, panic.
*/
template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__host__ int circularMoveCPU(T key, int cellId, T *const data, int *data_size,
                             const int bucket_n, CELL_T *cells,
                             const int cell_length, const int rand_seed) {
  // /*
  //     circular move
  //     1. check all virtual buckets of the influenced cell.
  //     2. move (copy and delete) all elements belonged to the influenced cell to
  //    a buffer. Record the elements in each bucket and remaining space in each
  //    bucket.
  //     3. find a valid strategy to update the cell.
  //     4. move all elements in the buffer to the corresponding bucket.

  //     return the number of successful inserted element.
  // */
  // std::vector<std::vector<T>> buffer(
  //     virtual_bucket_n, std::vector<T>()); // bucket serial as index
  // std::map<int, int> free_counter;         // bucket id as index
  // std::map<int, int> occupy_counter;       // bucket id as index

  // CELL_T offset = CELL_AT_I(cells, cellId);
  // int key_bs = HASH_BUCKET_S(key, rand_seed, offset,
  //                            virtual_bucket_n); // is already count the offset!!!
  // // if we talk about bucket serial, it has already counted in the offset.
  // // if it is does not count the offset, it is called virtual bucket id (vbi)

  // for (int vbi = 0; vbi < virtual_bucket_n; vbi++)
  // {
  //   int bucketId = HASH_BUCKET_ID(cellId, vbi, virtual_bucket_n,
  //                                 USED_CELLS_ARRAY_LENGTH(cell_length),
  //                                 bucket_n, rand_seed);
  //   free_counter[bucketId] = 0;
  //   for (int ei = 0; ei < bucket_cap; ei++)
  //   {
  //     T *elem = &BUCKET_I_ELEMENT_J(data, bucketId, ei, bucket_cap);
  //     if (!checkAllBitsSet(*elem))
  //     {
  //       int elem_cellId = HASH_CELL_ID(
  //           *elem, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
  //       if (cellId == elem_cellId)
  //       {
  //         int elem_bs = HASH_BUCKET_S(*elem, rand_seed, offset,
  //                                     virtual_bucket_n);
  //         if (elem_bs == vbi)
  //         {
  //           buffer[vbi].push_back(*elem);
  //           *elem = getAllBitsSet<T>();
  //           *data_size -= 1;
  //           free_counter[bucketId] += 1;
  //         }
  //       }
  //     }
  //     else
  //     {
  //       free_counter[bucketId] += 1;
  //     }
  //   }
  // }

  // buffer[key_bs].push_back(key);

  // // for each bucket bs, move all belonged elements to bucket (bs + offset) %
  // // virtual_bucket_n
  // CELL_T offset_delta = 1;
  // bool valid = false;
  // while ((offset + offset_delta) % virtual_bucket_n != offset)
  // {
  //   valid = true;
  //   occupy_counter.clear();
  //   for (int vbi = 0; vbi < virtual_bucket_n; vbi++)
  //   {
  //     int bucketId = HASH_BUCKET_ID(
  //         cellId, ((vbi + offset_delta) % virtual_bucket_n),
  //         virtual_bucket_n, USED_CELLS_ARRAY_LENGTH(cell_length),
  //         bucket_n, rand_seed);
  //     occupy_counter[bucketId] += buffer[vbi].size();
  //   }
  //   for (auto it = occupy_counter.begin(); it != occupy_counter.end();
  //        ++it)
  //   {
  //     int bucketId = it->first;
  //     int occupy = it->second;
  //     if (free_counter[bucketId] < occupy)
  //     {
  //       valid = false;
  //       break;
  //     }
  //   }
  //   if (valid)
  //     break;
  //   offset_delta += 1;
  //   offset_delta %= virtual_bucket_n;
  // }

  // if (valid)
  // {
  //   offset = CELL_AT_I(cells, cellId) = (offset + offset_delta) % virtual_bucket_n;
  // }
  // else
  // {
  //   // if it is unable to insert, give up the key to insert and restore the
  //   // original data.
  //   buffer[key_bs].pop_back();
  //   offset_delta = 0;
  // }

  // for (int from_vbi = 0; from_vbi < virtual_bucket_n; from_vbi++)
  // {
  //   int buffer_j = 0;
  //   int to_vbi = (from_vbi + offset_delta) % virtual_bucket_n;
  //   int to_bucket_id = HASH_BUCKET_ID(cellId, to_vbi, virtual_bucket_n,
  //                                     USED_CELLS_ARRAY_LENGTH(cell_length),
  //                                     bucket_n, rand_seed);
  //   for (int ei = 0; ei < bucket_cap; ei++)
  //   {
  //     if (buffer_j == (int)buffer[from_vbi].size())
  //       break;
  //     T *elem = &BUCKET_I_ELEMENT_J(data, to_bucket_id, ei, bucket_cap);
  //     if (checkAllBitsSet(*elem))
  //     {
  //       *elem = buffer[from_vbi][buffer_j];
  //       buffer_j++;
  //       *data_size += 1;
  //     }
  //   }
  //   if (buffer_j != (int)buffer[from_vbi].size())
  //   {
  //     panic("Bugs exists, {} != {}.", buffer_j, buffer[from_vbi].size());
  //   }
  // }

  // if (valid)
  // {
  //   return 1;
  // }
  // else
  // {
  //   return 0;
  // }
}

__host__ void setL2CachePersistence(void *ptrToGlobalMemoryPreferL2,
                                    size_t num_bytes, cudaStream_t &stream) {
  int device_id;
  cudaGetDevice(&device_id);
  cudaDeviceProp prop; // CUDA device properties variable
  cudaGetDeviceProperties(&prop, device_id);

  // Query GPU properties
  size_t size = min(num_bytes, getL2MaxPersistenceSizeInBytes());

  vclog(DEBUG,
        "Index on L2 required: {} bytes, configured max persistence l2 size: "
        "{} bytes, persisting L2 Cache Max Size: {} bytes",
        num_bytes, getL2MaxPersistenceSizeInBytes(),
        prop.persistingL2CacheMaxSize);
  if (num_bytes > size) {
    panic("Cannot allocate enough L2 side-aside cache for persistence");
  }

  cudaDeviceSetLimit(cudaLimitPersistingL2CacheSize,
                     size); // set-aside 3/4 of L2 cache for persisting
                            // accesses or the max allowed

  size_t window_size = min((size_t)prop.accessPolicyMaxWindowSize,
                           num_bytes); // Select minimum of user defined
                                       // num_bytes and max window size.

  vclog(INFO, "Max access policy window size is {} KB.",
        prop.accessPolicyMaxWindowSize / 1024.0);

  cudaStreamAttrValue
      stream_attribute; // Stream level attributes data structure
  stream_attribute.accessPolicyWindow.base_ptr =
      ptrToGlobalMemoryPreferL2; // Global Memory data pointer
                                 // Number of bytes for persistence access
#ifdef GLOBAL_AS_FAST_MEMORY
  stream_attribute.accessPolicyWindow.num_bytes =
      0; // Number of bytes for persistence access
#else
  stream_attribute.accessPolicyWindow.num_bytes = num_bytes;
#endif
  stream_attribute.accessPolicyWindow.hitRatio =
      1.0; // Hint for cache hit ratio
  stream_attribute.accessPolicyWindow.hitProp =
      cudaAccessPropertyPersisting; // Persistence Property
  stream_attribute.accessPolicyWindow.missProp =
      cudaAccessPropertyStreaming; // Type of access property on cache miss

  cudaStreamSetAttribute(
      stream, cudaStreamAttributeAccessPolicyWindow,
      &stream_attribute); // Set the attributes to a CUDA Stream
}

__host__ void resetL2CachePersistence(cudaStream_t &stream) {
  cudaStreamAttrValue stream_attribute;
  stream_attribute.accessPolicyWindow.num_bytes =
      0; // Setting the window size to 0 disable it
  cudaStreamSetAttribute(stream, cudaStreamAttributeAccessPolicyWindow,
                         &stream_attribute); // Overwrite the access policy
                                             // attribute to a CUDA Stream
  cudaCtxResetPersistingL2Cache();
}

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__host__ void
GPHOSGPUTableInsertValsCPU(const T *const vals, const int n, int *size,
                           T *const data, const int bucket_n, CELL_T *cells,
                           const int cell_length, const int rand_seed,
                           const int fail_limit) {
  //   int fail_cnt = 0;

  //   // reinsert buffer circle queue to store the items that needs to be
  //   // reinserted (triggered by cell split).
  //   int rcq_front = 0;
  //   int rcq_rear = 0;
  //   int rcq_size = MAX_CONCURRENT_CELL_SPLIT * virtual_bucket_n * bucket_cap;
  //   T *rcq = (T *)malloc(sizeof(T) * rcq_size);

  //   // debug metrics
  //   int max_size = 0;
  //   int direct_insert_count = 0;
  //   int circular_move_success_insert_count = 0;
  //   int circular_move_fail_insert_count = 0;
  //   int rcq_direct_insert_count = 0;
  //   int rcq_circular_move_success_insert_count = 0;
  //   int rcq_cell_split_count = 0;

  //   int triggered_insert = 0;
  //   int keyi = 0;
  //   while (keyi < n || !CQ_IS_EMPTY(rcq, rcq_front, rcq_rear, rcq_size))
  //   {
  //     bool is_rcq = false;
  //     triggered_insert += 1;
  //     if (triggered_insert >= (int)(MAX_INSERT_TRIGGERED_FACTOR * n))
  //     {
  //       vclog(WARN, "Insert kernel is stopped because too many inserts are "
  //                   "triggered.");
  //       break;
  //     }
  //     T key;
  // #ifdef CELL_SPLIT_ENABLED
  //     if (keyi < n)
  //     {
  //       key = vals[keyi];
  //       keyi++;
  //     }
  //     else if (!CQ_IS_EMPTY(rcq, rcq_front, rcq_rear, rcq_size))
  //     {
  //       key = CQ_HEAD(rcq, rcq_front, rcq_rear, rcq_size);
  //       CQ_POP(rcq, rcq_front, rcq_rear, rcq_size);
  //       is_rcq = true;
  //     }
  // #else
  //     key = vals[keyi];
  //     keyi++;
  // #endif

  // #ifdef CELL_SPLIT_ENABLED
  //     int cellId;
  //     CELL_T offset;
  //     int level;
  //     for (level = 0; level < MAX_ALLOW_CELL_SPLIT_LEVEL; level++)
  //     {
  //       cellId = HASH_CELL_ID(key, SPLIT_LEVEL_SEED(rand_seed, level),
  //                             USED_CELLS_ARRAY_LENGTH(cell_length));
  //       offset = CELL_AT_I(cells, cellId);
  //       if (offset < virtual_bucket_n)
  //       {
  //         break;
  //       }
  //     }
  //     if (level == MAX_ALLOW_CELL_SPLIT_LEVEL)
  //     {
  //       fail_cnt++;
  //     }
  // #else
  //     int cellId = HASH_CELL_ID(key, rand_seed,
  //                               USED_CELLS_ARRAY_LENGTH(cell_length));
  //     CELL_T offset = CELL_AT_I(cells, cellId); // will the offset be V? i.e., cell full
  // #endif

  //     if (fail_cnt <= fail_limit)
  //     {
  //       int bucketSerial = HASH_BUCKET_S(key, rand_seed, offset, virtual_bucket_n);
  //       int bucketId = HASH_BUCKET_ID(
  //           cellId, bucketSerial, virtual_bucket_n,
  //           USED_CELLS_ARRAY_LENGTH(cell_length), bucket_n, rand_seed);
  //       bool complete = false;
  //       for (int bi = 0; bi < bucket_cap; bi++)
  //       {
  //         T *elem = &BUCKET_I_ELEMENT_J(data, bucketId, bi, bucket_cap);
  //         if (checkAllBitsSet(*elem))
  //         {
  //           *elem = key;
  //           complete = true;
  //           *size += 1;
  //           if (!is_rcq)
  //           {
  //             direct_insert_count++;
  //           }
  //           else
  //           {
  //             rcq_direct_insert_count++;
  //           }
  //           break;
  //         }
  //       }
  //       // if bucket is full, do circular move
  //       if (!complete)
  //       {
  // #ifdef CYCULAR_MOVE_ENABLED
  //         // vclog(DEBUG, "Direct insert {} fail, start circular move on
  //         // cell {}", key, cellId);
  //         triggered_insert += bucket_cap * virtual_bucket_n;
  //         int circular_move_res = circularMoveCPU<T, bucket_cap, insert_group_size,
  //                                                 virtual_bucket_n>(key, cellId, data, size,
  //                                                                   bucket_n, cells,
  //                                                                   cell_length, rand_seed);
  //         // rcq, &rcq_front, &rcq_rear, rcq_size

  //         if (circular_move_res == 0)
  //         {
  //           circular_move_fail_insert_count++;
  // #ifdef CELL_SPLIT_ENABLED
  //           if (!is_rcq)
  //           {
  //             CQ_PUSH(rcq, rcq_front, rcq_rear, rcq_size, key);
  //             // vclog(DEBUG, "\tCircular move {} fail, push key into
  //             // rcq for reinsert later.", key);
  //           }
  //           else
  //           {
  //             triggered_insert += bucket_cap * virtual_bucket_n;
  //             int cell_split_res = cellSplit<T, bucket_cap, insert_group_size,
  //                                            virtual_bucket_n>(
  //                 key, cellId, data, size, bucket_n, cells,
  //                 cell_length, rand_seed, rcq, &rcq_front,
  //                 &rcq_rear, rcq_size);
  //             rcq_cell_split_count++;
  //             // vclog(DEBUG, "\t\tSplit cell {}.", cellId);
  //             if (cell_split_res == -1)
  //             {
  //               vclog(DEBUG, "Insert has been failed.");
  //               break;
  //             }
  //           }
  // #else
  //           // vclog(DEBUG, "Circular move {} fail, insert fails and
  //           // skips", key);
  //           fail_cnt++;
  // #endif
  //         }
  //         else
  //         {
  //           if (!is_rcq)
  //           {
  //             circular_move_success_insert_count++;
  //           }
  //           else
  //           {
  //             rcq_circular_move_success_insert_count++;
  //           }
  //         }
  // #else
  //         fail_cnt++;
  // #endif
  //       }
  //     }
  //     else
  //     {
  //       vclog(DEBUG,
  //             "Insert has been failed for more than {} times, aborted.",
  //             fail_limit);
  //       break;
  //     }
  //     max_size = max_size > (*size) ? max_size : (*size);
  //   }
  //   vclog(DEBUG,
  //         "=============Metrics=============\n"
  //         "max_size_reached\t {}\n"
  //         "table_size\t {}\n"
  //         "insert_n\t {}\n"
  //         "load_factor\t {}\n"
  //         "direct_insert_count\t {}\n"
  //         "circular_move_success_insert_count\t {}\n"
  //         "circular_move_fail_insert_count\t {}\n"
  //         "rcq_direct_insert_count\t {}\n"
  //         "rcq_circular_move_success_insert_count\t {}\n"
  //         "rcq_cell_split_count\t {}\n"
  //         "=================================",
  //         max_size, *size, n, (*size) * 1.0 / (bucket_cap * bucket_n),
  //         direct_insert_count, circular_move_success_insert_count,
  //         circular_move_fail_insert_count, rcq_direct_insert_count,
  //         rcq_circular_move_success_insert_count, rcq_cell_split_count);
  //   free(rcq);
}

template <typename T>
void adjust_CSI(const T *const vals, const int n, T *csi_block_vals,
                size_t *csi_block_ptrs, size_t *csi_block_end_ptrs,
                size_t *vals_loc, const int rand_seed, const int cell_length) {
  int sm_cell_block_length = (int)ceil(cell_length * 1.0 / BLOCK_COUNT);

  int *csi_block_size = new int[BLOCK_COUNT];
  memset(csi_block_size, 0, sizeof(int) * BLOCK_COUNT);
  cudaMemset(csi_block_ptrs, 0xff, sizeof(size_t) * BLOCK_COUNT);
  cudaMemset(csi_block_end_ptrs, 0xff, sizeof(size_t) * BLOCK_COUNT);
  for (int i = 0; i < n; i++) {
    int sm_id =
        KEY_TO_SM_ID(vals[i], rand_seed, cell_length, sm_cell_block_length);
    csi_block_size[sm_id]++;
  }

  int cur = 0;
  for (int i = 0; i < BLOCK_COUNT; i++) {
    if (csi_block_size[i] > 0) {
      csi_block_ptrs[i] = cur;
      cur += csi_block_size[i];
      csi_block_end_ptrs[i] = cur;
    }
  }
  memset(csi_block_size, 0, sizeof(int) * BLOCK_COUNT);

  for (int i = 0; i < n; i++) {
    int sm_id =
        KEY_TO_SM_ID(vals[i], rand_seed, cell_length, sm_cell_block_length);
    int loc = csi_block_ptrs[sm_id] + csi_block_size[sm_id];
    csi_block_vals[loc] = vals[i];
    vals_loc[i] = loc;
    csi_block_size[sm_id]++;
  }
  delete[] csi_block_size;
}

#ifdef CROSS_SM_INDEX

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                   virtual_bucket_n>::lookup_vals_CSI(const T *const vals,
                                                      bool *const results,
                                                      const int n,
                                                      UnifiedTimeRecorder
                                                          *recorder) {
#ifdef DISABLE_VECTORIZATION_AND_INSTRUCTION_PARALLEL
  fmt::print("DISABLE_VECTORIZATION_AND_INSTRUCTION_PARALLEL lookupCSI\n");
#else
  fmt::print("ENABLE_VECTORIZATION_AND_INSTRUCTION_PARALLEL lookupCSI\n");
#endif

  // Allocate GPU memory space.

  T *csi_block_vals;
  size_t *csi_block_ptrs;
  size_t *csi_block_end_ptrs;

  cudaMallocManaged((void **)&csi_block_vals, n * sizeof(T));
  cudaMallocManaged((void **)&csi_block_ptrs, (BLOCK_COUNT) * sizeof(size_t));
  cudaMallocManaged((void **)&csi_block_end_ptrs,
                    (BLOCK_COUNT) * sizeof(size_t));

  cudaMemAdvise(csi_block_vals, (n * sizeof(T)), cudaMemAdviseSetAccessedBy, 0);
  cudaMemPrefetchAsync(csi_block_vals, (n * sizeof(T)), 0);

  cudaMemAdvise(csi_block_ptrs, (BLOCK_COUNT * sizeof(size_t)),
                cudaMemAdviseSetAccessedBy, 0);
  cudaMemPrefetchAsync(csi_block_ptrs, (BLOCK_COUNT * sizeof(size_t)), 0);

  cudaMemAdvise(csi_block_end_ptrs, (n * sizeof(size_t)),
                cudaMemAdviseSetAccessedBy, 0);
  cudaMemPrefetchAsync(csi_block_end_ptrs, (n * sizeof(size_t)), 0);

  size_t *vals_loc = new size_t[n];

  int sm_cell_block_length = (int)ceil(_cells_length * 1.0 / BLOCK_COUNT);

  // preprocess _vals to _csi_ready_vals[BLOCK_COUNT] and
  // _csi_ready_vals_n[BLOCK_COUNT]

  if (recorder) {
    recorder->start_timer("preprocessing", false); // not GPU now
  }

  vclog(INFO, "Start preprocessing", BLOCK_COUNT, GPHOS_BLOCK_SIZE);
  adjust_CSI<T>(vals, n, csi_block_vals, csi_block_ptrs, csi_block_end_ptrs,
                vals_loc, _rand_seed, _cells_length);

  if (recorder) {
    recorder->finish_timer("preprocessing");
    recorder->start_timer("lookup_cudaMalloc&cudaMemcpyHostToDevice", true);
  }

  bool *csi_results;
  cudaMallocManaged((void **)&csi_results, n * sizeof(bool));

  cudaMemAdvise(csi_results, (n * sizeof(bool)), cudaMemAdviseSetAccessedBy,
                0);
  cudaMemPrefetchAsync(csi_results, (n * sizeof(bool)), 0);

  // copy data to device
  vclog(INFO, "Start Memcpy", BLOCK_COUNT, GPHOS_BLOCK_SIZE);

  if (recorder) {
    recorder->finish_timer("lookup_cudaMalloc&cudaMemcpyHostToDevice");
    recorder->start_timer("lookup_kernel", true);
  }

  vclog(INFO,
        "launch GPHOSGPUTableLookupValsKernel, numBlocks {}, "
        "threadsPerBlock {}",
        BLOCK_COUNT, GPHOS_BLOCK_SIZE);

  cudaStream_t stream;
  cudaStreamCreate(&stream);

  if ((size_t)((sm_cell_block_length) * sizeof(CELL_T)) >
      (size_t)SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE) {
    panic("Too large index size.");
  }

  // lauch kernel
  GPHOSGPUTableLookupValsCSIKernel<T, bucket_cap, lookup_group_size,
                                   virtual_bucket_n>
      <<<BLOCK_COUNT, GPHOS_BLOCK_SIZE,
         min((size_t)((sm_cell_block_length) * sizeof(CELL_T)),
             (size_t)SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE),
         stream>>>(csi_block_vals, csi_block_ptrs, csi_block_end_ptrs,
                   csi_results, _data, _bucket_n, _cells, _cells_length,
                   _rand_seed);
  cudaError_t cudaerr = cudaDeviceSynchronize();
  gpuErrchk(cudaerr);

  if (recorder) {
    recorder->finish_timer("lookup_kernel");
    recorder->start_timer("lookup_cudaMemcpyDeviceToHost&cudaFree", true);
  }

  vclog(INFO, "Start copy back and free", BLOCK_COUNT, GPHOS_BLOCK_SIZE);

  // Copy back and Free

  cudaFree(csi_block_vals);
  // cudaFree(csi_block_ptrs);
  cudaFree(csi_block_end_ptrs);
  // cudaFree(csi_results);

  if (recorder) {
    recorder->finish_timer("lookup_cudaMemcpyDeviceToHost&cudaFree");
    recorder->start_timer("postprocessing", false); // Not GPU now
  }

  vclog(INFO, "Start postprocessing", BLOCK_COUNT, GPHOS_BLOCK_SIZE);

  finalize_CSI<bool>(results, csi_results, csi_block_ptrs, vals_loc, n);

  cudaFree(csi_results);
  cudaFree(csi_block_ptrs);
  delete[] vals_loc;

  if (recorder) {
    recorder->finish_timer("postprocessing");
  }
}

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                   virtual_bucket_n>::
    lookup_key_return_value_CSI(const typename HalfTypeT<T>::HT *const keys,
                                typename HalfTypeT<T>::HT *const return_values,
                                const int n, UnifiedTimeRecorder *recorder) {
  using HT = typename HalfTypeT<T>::HT;
#ifdef DISABLE_VECTORIZATION_AND_INSTRUCTION_PARALLEL
  fmt::print("DISABLE_VECTORIZATION_AND_INSTRUCTION_PARALLEL lookupCSI\n");
#else
  fmt::print("ENABLE_VECTORIZATION_AND_INSTRUCTION_PARALLEL lookupCSI\n");
#endif

  // Allocate GPU memory space.

  HT *csi_block_keys;
  cudaMallocManaged(&csi_block_keys, sizeof(HT) * n);

  size_t *csi_block_ptrs;
  size_t *csi_block_end_ptrs;
  size_t *csi_block_vals;
  cudaMallocManaged((void **)&csi_block_vals, n * sizeof(T));
  cudaMallocManaged((void **)&csi_block_ptrs, (BLOCK_COUNT) * sizeof(size_t));
  cudaMallocManaged((void **)&csi_block_end_ptrs,
                    (BLOCK_COUNT) * sizeof(size_t));

  cudaMemAdvise(csi_block_keys, (n * sizeof(HT)), cudaMemAdviseSetAccessedBy,
                0);
  cudaMemPrefetchAsync(csi_block_keys, (n * sizeof(HT)), 0);

  cudaMemAdvise(csi_block_vals, (n * sizeof(T)), cudaMemAdviseSetAccessedBy, 0);
  cudaMemPrefetchAsync(csi_block_vals, (n * sizeof(T)), 0);

  cudaMemAdvise(csi_block_ptrs, (BLOCK_COUNT * sizeof(size_t)),
                cudaMemAdviseSetAccessedBy, 0);
  cudaMemPrefetchAsync(csi_block_ptrs, (BLOCK_COUNT * sizeof(size_t)), 0);

  cudaMemAdvise(csi_block_end_ptrs, (n * sizeof(size_t)),
                cudaMemAdviseSetAccessedBy, 0);
  cudaMemPrefetchAsync(csi_block_end_ptrs, (n * sizeof(size_t)), 0);

  size_t *vals_loc = new size_t[n];

  HT *csi_return_values;
  cudaMallocManaged(&csi_return_values, sizeof(HT) * n);

  cudaMemAdvise(csi_return_values, (n * sizeof(HT)), cudaMemAdviseSetAccessedBy,
                0);
  cudaMemPrefetchAsync(csi_return_values, (n * sizeof(HT)), 0);
  int sm_cell_block_length = (int)ceil(_cells_length * 1.0 / BLOCK_COUNT);

  // preprocess _vals to _csi_ready_vals[BLOCK_COUNT] and
  // _csi_ready_vals_n[BLOCK_COUNT]

  if (recorder) {
    recorder->start_timer("preprocessing", false); // not GPU now
  }
  adjust_CSI<HT>(keys, n, csi_block_keys, csi_block_ptrs, csi_block_end_ptrs,
                 vals_loc, _rand_seed, _cells_length);
  // for (int blockId = 0; blockId < BLOCK_COUNT; blockId++) {
  //   for (int i = csi_block_ptrs[blockId]; i < csi_block_end_ptrs[blockId]; i++){
  //     HT key = csi_block_keys[i];
  //     int globalCellId = HASH_CELL_ID(key, _rand_seed, _cells_length);
  //     fmt::print("HASH_CELL_ID({}, {}, {})={}", key, _rand_seed, _cells_length, globalCellId);
  //     int localCellId = (globalCellId) - (blockId) * (sm_cell_block_length);
  //     int shouldBeInBlockId = globalCellId / sm_cell_block_length;
  //     fmt::print("key {}, blockId {}, shouldBeInBlockId {}, globalCellId {}, localCellId {}\n", key, blockId, shouldBeInBlockId, globalCellId, localCellId);
  //     assert(localCellId >= 0 && localCellId < sm_cell_block_length && shouldBeInBlockId == blockId);
  //   }
  // }

  if (recorder) {
    recorder->start_timer("lookup_cudaMalloc&cudaMemcpyHostToDevice", true);
  }

  // copy data to device
  vclog(INFO, "Start Memcpy", BLOCK_COUNT, GPHOS_BLOCK_SIZE);

  if (recorder) {
    recorder->finish_timer("lookup_cudaMalloc&cudaMemcpyHostToDevice");
    recorder->start_timer("lookup_kernel", true);
  }

  vclog(INFO,
        "launch GPHOSGPUTableLookupValsKernel, numBlocks {}, "
        "threadsPerBlock {}",
        BLOCK_COUNT, GPHOS_BLOCK_SIZE);

  cudaStream_t stream;
  cudaStreamCreate(&stream);

  if ((size_t)((sm_cell_block_length) * sizeof(CELL_T)) >
      (size_t)SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE) {
    panic("Too large index size.");
  } else {
    vclog(INFO, "cell index per block length {} ({} bytes)",
          sm_cell_block_length, (sm_cell_block_length) * sizeof(CELL_T));
  }

  // lauch kernel
#ifndef TEMP_CELL_IN_GLOBAL
  cudaFuncSetAttribute(GPHOSGPUTableLookupKeyReturnValueCSIKernel<
                           T, bucket_cap, lookup_group_size, virtual_bucket_n>,
                       cudaFuncAttributeMaxDynamicSharedMemorySize,
                       (sm_cell_block_length) * sizeof(CELL_T));
  GPHOSGPUTableLookupKeyReturnValueCSIKernel<T, bucket_cap, lookup_group_size,
                                             virtual_bucket_n>
      <<<BLOCK_COUNT, GPHOS_BLOCK_SIZE,
         min((size_t)((sm_cell_block_length) * sizeof(CELL_T)),
             (size_t)SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE),
         stream>>>(csi_block_keys, csi_block_ptrs, csi_block_end_ptrs,
                   csi_return_values, _data, _bucket_n, _cells, _cells_length,
                   _rand_seed);
#else
  GPHOSGPUTableLookupKeyReturnValueCSIKernel<T, bucket_cap, lookup_group_size,
                                             virtual_bucket_n>
      <<<BLOCK_COUNT, GPHOS_BLOCK_SIZE, 0, stream>>>(
          csi_block_keys, csi_block_ptrs, csi_block_end_ptrs, csi_return_values,
          _data, _bucket_n, _cells, _cells_length, _rand_seed);
#endif
  cudaError_t cudaerr = cudaDeviceSynchronize();
  gpuErrchk(cudaerr);

  if (recorder) {
    recorder->finish_timer("lookup_kernel");
    recorder->start_timer("lookup_cudaMemcpyDeviceToHost&cudaFree", true);
  }

  vclog(INFO, "Start copy back and free", BLOCK_COUNT, GPHOS_BLOCK_SIZE);

  // Copy back and Free

  cudaFree(csi_block_keys);
  cudaFree(csi_block_end_ptrs);
  finalize_CSI<HT>(return_values, csi_return_values, csi_block_ptrs, vals_loc,
                   n);
  if (recorder) {
    recorder->finish_timer("lookup_cudaMemcpyDeviceToHost&cudaFree");
  }
  cudaFree(csi_block_ptrs);
  cudaFree(csi_return_values);
  cudaFree(csi_block_keys);
  delete[] vals_loc;
}
#endif

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                   virtual_bucket_n>::lookup_vals(const T *const vals,
                                                  bool *const results,
                                                  const int n,
                                                  UnifiedTimeRecorder
                                                      *recorder) {
  if (bucket_cap < lookup_group_size || bucket_cap % lookup_group_size != 0) {
    panic("bucket_cap must larger than group_size and %% group_size must "
          "be 0, "
          "otherwise there will be some problem in kernel. Maybe handled "
          "in the "
          "future.");
  }
  if (lookup_group_size > bucket_cap) {
    panic("group_size > bucket_cap is not allowed.");
  }

#ifdef CROSS_SM_INDEX
  lookup_vals_CSI(vals, results, n, recorder);
#else

  // Allocate GPU memory space.
  T *d_data;
  CELL_T *d_cells;

  T *d_vals;
  bool *d_results;

  if (recorder) {
    recorder->start_timer("lookup_cudaMalloc&cudaMemcpyHostToDevice", true);
  }

  cudaMalloc((void **)&d_data, _bucket_n * bucket_cap * sizeof(T));
  cudaMalloc((void **)&d_cells,
             (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(CELL_T));

  cudaMalloc((void **)&d_vals, n * sizeof(T));
  cudaMalloc((void **)&d_results, n * sizeof(bool));

  // copy data to device
  cudaMemcpy(d_vals, vals, n * sizeof(T), cudaMemcpyHostToDevice);
  cudaMemcpy(d_data, _data, _bucket_n * bucket_cap * sizeof(T),
             cudaMemcpyHostToDevice);
  cudaMemcpy(d_cells, _cells,
             (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(CELL_T),
             cudaMemcpyHostToDevice);

  if (recorder) {
    recorder->finish_timer("lookup_cudaMalloc&cudaMemcpyHostToDevice");
    recorder->start_timer("lookup_kernel", true);
  }

  vclog(DEBUG,
        "lauch GPHOSGPUTableLookupValsKernel, numBlocks {}, threadsPerBlock "
        "{}",
        (int)ceil((double)n / GPHOS_BLOCK_SIZE), GPHOS_BLOCK_SIZE);

  cudaStream_t stream;
  cudaStreamCreate(&stream);

#ifdef L2_AS_FAST_MEMORY
  if (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length) * sizeof(CELL_T) >
      SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE) {
    setL2CachePersistence(reinterpret_cast<void *>(PTR_TO_INDEX_IN_L2(d_cells)),
                          ACTUAL_CELLS_ARRAY_LENGTH(_cells_length) *
                                  sizeof(CELL_T) -
                              SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE,
                          stream);
  }
#endif

  // lauch kernel
  GPHOSGPUTableLookupValsKernel<T, bucket_cap, lookup_group_size,
                                virtual_bucket_n>
      <<<BLOCK_COUNT, GPHOS_BLOCK_SIZE,
         min((size_t)((ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) *
                      sizeof(CELL_T)),
             (size_t)SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE),
         stream>>>(d_vals, d_results, n, d_data, _bucket_n, d_cells,
                   _cells_length, _rand_seed);
  // gpuErrchk( cudaPeekAtLastError() );
  cudaDeviceSynchronize();

#ifdef L2_AS_FAST_MEMORY
  resetL2CachePersistence(stream);
#endif

  if (recorder) {
    recorder->finish_timer("lookup_kernel");
    recorder->start_timer("lookup_cudaMemcpyDeviceToHost&cudaFree", true);
  }

  // Copy back and Free
  cudaMemcpy(_data, d_data, _bucket_n * bucket_cap * sizeof(T),
             cudaMemcpyDeviceToHost);
  cudaMemcpy(_cells, d_cells,
             (ACTUAL_CELLS_ARRAY_LENGTH(_cells_length)) * sizeof(CELL_T),
             cudaMemcpyDeviceToHost);
  cudaMemcpy(results, d_results, n * sizeof(bool), cudaMemcpyDeviceToHost);

  cudaFree(d_vals);
  cudaFree(d_data);
  cudaFree(d_cells);
  cudaFree(d_results);

  if (recorder) {
    recorder->finish_timer("lookup_cudaMemcpyDeviceToHost&cudaFree");
  }
#endif
}

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                   virtual_bucket_n>::lookup_vals_CPU(const T *const vals,
                                                      bool *const results,
                                                      const int n) {
  std::set<T> cpu_hash_table =
      std::set<T>(&_data[0], &_data[0] + (_bucket_n * bucket_cap));
  for (int i = 0; i < n; i++) {
    T key = vals[i];
    results[i] = (cpu_hash_table.count(key) > 0);
  }
}

__device__ unsigned getWarpMask(int group_size, int thread_id) {
  if (group_size == 32)
    return 0xffffffff;
  return ((0x1 << group_size) - 1)
         << (((thread_id % 32) / group_size) * group_size);
}

// TODO: validate; do a dummy insert first and check this.
// TODO: validate the coalesed access of the bucket.
// TODO: consider counter after complete insert.
template <typename T, int bucket_cap, int lookup_group_size,
          int virtual_bucket_n>
__global__ void
GPHOSGPUTableLookupValsKernel(const T *const vals, bool *const results,
                              const int n, T *const data, const int bucket_n,
                              const CELL_T *cells, const int cell_length,
                              const int rand_seed) {
  // compile-time const
  constexpr int TOTAL_TURN = bucket_cap / lookup_group_size;
  constexpr int KEY_SIZE = sizeof(T);
  constexpr int VECTOR_LEN =
      (16 < (TOTAL_TURN * KEY_SIZE) ? 16 : (TOTAL_TURN * KEY_SIZE)) / KEY_SIZE;
  using V = CUDAVectorType_t<T, VECTOR_LEN>;

  /*
      The data are stored in "data" in format of bucket, the bucket capibility
      is likely to be 32 or multiply of 32.
      The cells are firstly copied to shared memory.
      The warp is the unit to process the request, so every 32 threads are
     working together to handle one lookup in "vals".

      For a warp processing a request, they firstly get the cell by computing
     the hash1 of the request, then they get the cell offset (we can do this by
     one thread get the value and broadcast by __shfl_sync).

      Then use hash2 as the bucket function to transfer cell id j to bucket id,
      id(i) = (hash2((j<<10) | (i)) ) % bucket_n.

      Use hash3 to get the bucket i.
      bucket_i = (hash3(key) + offset) % virtual_bucket_n
      bucket_id = id(bucket_i)

      Get the bucket content, the warp works together to get the bucket with
     coalesced access.
  */
  int idGlobal = threadIdx.x + blockIdx.x * blockDim.x;
  int groupLane =
      threadIdx.x % lookup_group_size; // groupLane is the serial in a group (a
                                       // group could be different from a warp)
  int groupId = idGlobal / lookup_group_size;
  int groupN = blockDim.x * gridDim.x / lookup_group_size;
  extern __shared__ CELL_T shared[];
  unsigned group_mask = getWarpMask(lookup_group_size, threadIdx.x);
  const CELL_T *cells_l2_pointer = PTR_TO_INDEX_IN_L2(cells);

  // copy cells array to shared mem
  int copyId = threadIdx.x;

#ifdef L2_AS_FAST_MEMORY
  while (copyId < min((int)ACTUAL_CELLS_ARRAY_LENGTH(cell_length),
                      (int)(SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE /
                            sizeof(CELL_T)))) // cell_length
  {
    shared[copyId] = cells[copyId];
    // printf("tid: %d, copy id: %d, copy to shared memory.\n", threadIdx.x,
    // copyId);
    copyId += blockDim.x;
  }
#else
  while (copyId < (ACTUAL_CELLS_ARRAY_LENGTH(cell_length))) // cell_length
  {
    shared[copyId] = cells[copyId];
    // printf("tid: %d, copy id: %d, copy to shared memory.\n", threadIdx.x,
    // copyId);
    copyId += blockDim.x;
  }
#endif

  __syncthreads();
  // __threadfence_block();

#ifdef NKPR
  size_t group_block_size = (size_t)ceil(n * 1.0 / groupN);
  size_t group_start_ptr = groupId * group_block_size;
  size_t group_end_ptr = (groupId + 1) * group_block_size;
#endif

  // each request is processed by a warp

#ifdef NKPR
  for (int i = group_start_ptr; i < group_end_ptr; i += lookup_group_size) {
    size_t max_groupLane = min(group_end_ptr - i, (size_t)lookup_group_size);
    T own_key;
    if (groupLane < max_groupLane)
      own_key = vals[i + groupLane];
    int own_res;
    for (int j = 0; j < lookup_group_size; j++) {
      T key = __shfl_sync(group_mask, own_key, j, lookup_group_size);
      int cellId =
          HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
      int lookup_res =
          lookupBucketForTargetKey<T, bucket_cap, lookup_group_size,
                                   virtual_bucket_n>(
              key, data, bucket_n, cellId, cellId, cells, cell_length,
              groupLane, group_mask, rand_seed);
      if (groupLane == j)
        own_res = lookup_res;
    }
    if (groupLane < max_groupLane)
      results[i + groupLane] = (own_res != 0);
  }
#else
  for (int i = groupId; i < n; i += groupN) {
    T key;
    if (groupLane == 0)
      key = vals[i];
    key = __shfl_sync(group_mask, key, 0, lookup_group_size);

    // Get the cell id
    int cellId =
        HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
    int lookup_res = lookupBucketForTargetKey<T, bucket_cap, lookup_group_size,
                                              virtual_bucket_n>(
        key, data, bucket_n, cellId, cellId, cells, cell_length, groupLane,
        group_mask, rand_seed);
    if (groupLane == 0) {
      results[i] = (lookup_res != 0);
    }
  }
#endif
}

template <typename T, int bucket_cap, int lookup_group_size,
          int virtual_bucket_n>
__device__ inline int lookupBucketForTargetKey(
    const T key, T *const data, const int bucket_n, const int globalCellId,
    const int localCellId, const CELL_T *cells, const int cell_length,
    const int groupLane, const unsigned group_mask, const int rand_seed) {
  // compile-time const
  constexpr int TOTAL_TURN = bucket_cap / lookup_group_size;
  constexpr int KEY_SIZE = sizeof(T);
  constexpr int VECTOR_LEN =
      (16 < (TOTAL_TURN * KEY_SIZE) ? 16 : (TOTAL_TURN * KEY_SIZE)) / KEY_SIZE;
  using V = CUDAVectorType_t<T, VECTOR_LEN>;
  extern __shared__ CELL_T shared[];

  int res;

  // Get the offset
  CELL_T cell_value;
  if (groupLane == 0) {
    cell_value = CELL_AT_I_GPU(shared, cells_l2_pointer, localCellId);
  }
  cell_value = __shfl_sync(group_mask, cell_value, 0, lookup_group_size);
  CELL_T offset = GET_OFFSET_FROM_CELL(cell_value, virtual_bucket_n);
  CELL_T cvbid = GET_CVBID_FROM_CELL(cell_value, virtual_bucket_n);

  // Cal the bucket serial
  int bucketSerial = HASH_BUCKET_S(key, rand_seed, offset, virtual_bucket_n);

  // Cal the bucket id
  int bucketId = HASH_BUCKET_ID(globalCellId, bucketSerial, virtual_bucket_n,
                                USED_CELLS_ARRAY_LENGTH(cell_length), cvbid,
                                bucket_n, rand_seed);
  __syncwarp(group_mask);

  // if (groupLane == 0) printf("GPU msg\t==========\toffset = %hu, bs = %d,
  // bid = %d\n", offset, bucketSerial, bucketId);

  res = 0;
#ifdef DISABLE_VECTORIZATION_AND_INSTRUCTION_PARALLEL
  for (int j = 0; j < TOTAL_TURN; j++) {
    // Access the bucket in global memory
    T elem = BUCKET_I_ELEMENT_J(
        data, bucketId, groupLane + (lookup_group_size * j), bucket_cap);

    // Check whether key exists
    res = __any_sync(group_mask, key == elem);
    if (res != 0)
      break;
  }
#else
  V slots_vec[TOTAL_TURN / VECTOR_LEN];
#pragma unroll
  for (int j = 0; j < TOTAL_TURN / VECTOR_LEN; j++) {
    slots_vec[j] = BUCKET_I_ELEMENT_J(
        reinterpret_cast<V *>(data), bucketId,
        SLOT(groupLane, lookup_group_size, j, TOTAL_TURN / VECTOR_LEN),
        bucket_cap / VECTOR_LEN);
  }

  T slots[VECTOR_LEN];
  // splitVector<T, VECTOR_LEN>(slots+j, vec);
  for (int j = 0; j < TOTAL_TURN / VECTOR_LEN; j++) {
    splitVector<T, VECTOR_LEN>(slots, slots_vec[j]);
    for (int k = 0; k < VECTOR_LEN; k++) {
      if (res = __any_sync(group_mask, slots[k] == key)) {
        break;
      }
    }
    if (res)
      break;
  }
#endif
  return res;
}

template <typename T, int bucket_cap, int lookup_group_size,
          int virtual_bucket_n>
__device__ inline typename HalfTypeT<T>::HT lookupBucketForTargetKeyReturnValue(
    const typename HalfTypeT<T>::HT key, T *const data, const int bucket_n,
    const int globalCellId, const int localCellId, const CELL_T *cells,
    const int cell_length, const int groupLane, const unsigned group_mask,
    const int rand_seed) {
  using HT = typename HalfTypeT<T>::HT;
  // compile-time const
  constexpr int TOTAL_TURN = bucket_cap / lookup_group_size;
  constexpr int KV_SIZE = sizeof(T);
  constexpr int VECTOR_LEN =
      (16 < (TOTAL_TURN * KV_SIZE) ? 16 : (TOTAL_TURN * KV_SIZE)) / KV_SIZE;
  using V = CUDAVectorType_t<T, VECTOR_LEN>;

#ifndef TEMP_CELL_IN_GLOBAL
  extern __shared__ CELL_T shared[];
#endif

  HT res;

  // Get the offset
  CELL_T cell_value;
  if (groupLane == 0) {
#ifdef TEMP_CELL_IN_GLOBAL
    volatile const CELL_T *cells_on_global = cells;
    cell_value = CELL_AT_I_GPU(cells_on_global, cells_l2_pointer, globalCellId);
#else
    cell_value = CELL_AT_I_GPU(shared, cells_l2_pointer, localCellId);
#endif
  }

  cell_value = __shfl_sync(group_mask, cell_value, 0, lookup_group_size);
  CELL_T offset = GET_OFFSET_FROM_CELL(cell_value, virtual_bucket_n);
  CELL_T cvbid = GET_CVBID_FROM_CELL(cell_value, virtual_bucket_n);

  // Cal the bucket serial
  int bucketSerial = HASH_BUCKET_S(key, rand_seed, offset, virtual_bucket_n);

  // Cal the bucket id
  int bucketId = HASH_BUCKET_ID(globalCellId, bucketSerial, virtual_bucket_n,
                                USED_CELLS_ARRAY_LENGTH(cell_length), cvbid,
                                bucket_n, rand_seed);
  __syncwarp(group_mask);

  // if (groupLane == 0) printf("GPU msg\t==========\toffset = %hu, bs = %d,
  // bid = %d\n", offset, bucketSerial, bucketId);

  res = 0;
#ifdef DISABLE_VECTORIZATION_AND_INSTRUCTION_PARALLEL
  for (int j = 0; j < TOTAL_TURN; j++) {
    // Access the bucket in global memory
    T kv = BUCKET_I_ELEMENT_J(data, bucketId,
                              groupLane + (lookup_group_size * j), bucket_cap);
    HT found_key, found_value;
    __syncwarp(group_mask);
    splitKV(kv, found_key, found_value);

    // Check whether key exists
    int hit_lane = ballotLowestWarpLaneIdWithTrue(key == found_key, group_mask);
    if (hit_lane >= 0) {
      res = __shfl_sync(group_mask, found_value, hit_lane, lookup_group_size);
      break;
    }
  }
#else
  V slots_vec[TOTAL_TURN / VECTOR_LEN];
#pragma unroll
  for (int j = 0; j < TOTAL_TURN / VECTOR_LEN; j++) {
    slots_vec[j] = BUCKET_I_ELEMENT_J(
        reinterpret_cast<V *>(data), bucketId,
        SLOT(groupLane, lookup_group_size, j, TOTAL_TURN / VECTOR_LEN),
        bucket_cap / VECTOR_LEN);
  }

  T slots[VECTOR_LEN];
  // splitVector<T, VECTOR_LEN>(slots+j, vec);
  for (int j = 0; j < TOTAL_TURN / VECTOR_LEN; j++) {
    splitVector<T, VECTOR_LEN>(slots, slots_vec[j]);
    for (int k = 0; k < VECTOR_LEN; k++) {
      HT found_key, found_value;
      splitKV(slots[k], found_key, found_value);
      // Check whether key exists
      int hit_lane =
          ballotLowestWarpLaneIdWithTrue(key == found_key, group_mask);
      if (hit_lane >= 0) {
        res = __shfl_sync(group_mask, found_value, hit_lane, lookup_group_size);
        break;
      }
    }
    if (res)
      break;
  }
#endif
  return res;
}

#ifdef CROSS_SM_INDEX
template <typename T, int bucket_cap, int lookup_group_size,
          int virtual_bucket_n>
__global__ void GPHOSGPUTableLookupValsCSIKernel(
    const T *csi_block_vals, const size_t *csi_block_ptrs,
    const size_t *csi_block_end_ptrs, bool *csi_results, T *const data,
    const int bucket_n, const CELL_T *cells, const int cell_length,
    const int rand_seed) {
  // compile-time const
  constexpr int TOTAL_TURN = bucket_cap / lookup_group_size;
  constexpr int KEY_SIZE = sizeof(T);
  constexpr int VECTOR_LEN =
      (16 < (TOTAL_TURN * KEY_SIZE) ? 16 : (TOTAL_TURN * KEY_SIZE)) / KEY_SIZE;
  using V = CUDAVectorType_t<T, VECTOR_LEN>;
  /*
      The data are stored in "data" in format of bucket, the bucket capibility
      is likely to be 32 or multiply of 32.
      The cells are firstly copied to shared memory.
      The warp is the unit to process the request, so every 32 threads are
     working together to handle one lookup in "vals".

      For a warp processing a request, they firstly get the cell by computing
     the hash1 of the request, then they get the cell offset (we can do this by
     one thread get the value and broadcast by __shfl_sync).

      Then use hash2 as the bucket function to transfer cell id j to bucket id,
      id(i) = (hash2((j<<10) | (i)) ) % bucket_n.

      Use hash3 to get the bucket i.
      bucket_i = (hash3(key) + offset) % virtual_bucket_n
      bucket_id = id(bucket_i)

      Get the bucket content, the warp works together to get the bucket with
     coalesced access.
  */
  // int idGlobal = threadIdx.x + blockIdx.x * blockDim.x;
  int groupLane =
      threadIdx.x % lookup_group_size; // groupLane is the serial in a group (a
                                       // group could be different from a warp)
  int groupId = threadIdx.x / lookup_group_size;
  int groupN = blockDim.x / lookup_group_size;
  int smId = blockIdx.x;
  extern __shared__ CELL_T shared[];
  unsigned group_mask = getWarpMask(lookup_group_size, threadIdx.x);
  int sm_cell_block_length = (int)ceil(cell_length * 1.0 / BLOCK_COUNT);

  // copy cells array to shared mem
  int copyId = threadIdx.x;

  while (copyId < sm_cell_block_length &&
         smId * sm_cell_block_length + copyId < cell_length) // cell_length
  {
    shared[copyId] = cells[smId * sm_cell_block_length + copyId];
    // printf("GPU msg\t==========\tshared[%d] = cells[%d * %d + %d]\n",
    // copyId, smId, sm_cell_block_length, copyId);
    copyId += blockDim.x;
  }

  size_t sm_ptr;
  size_t sm_end_ptr;
  if (groupLane == 0) {
    sm_ptr = csi_block_ptrs[smId];
    sm_end_ptr = csi_block_end_ptrs[smId];
  }
  sm_ptr = __shfl_sync(group_mask, sm_ptr, 0, lookup_group_size);
  sm_end_ptr = __shfl_sync(group_mask, sm_end_ptr, 0, lookup_group_size);

#ifdef NKPR
  size_t group_block_size = (size_t)ceil((sm_end_ptr - sm_ptr) * 1.0 / groupN);
  size_t group_start_ptr = sm_ptr + groupId * group_block_size;
  size_t group_end_ptr =
      min(sm_end_ptr, sm_ptr + (groupId + 1) * group_block_size);
#endif

  __syncthreads();
  // __threadfence_block();

  // each request is processed by a warp
  if (sm_ptr < sm_end_ptr) {
#ifdef NKPR
    for (int i = group_start_ptr; i < group_end_ptr; i += lookup_group_size) {
      T own_key;
      int own_res;
      int max_groupLane = min(group_end_ptr - i, (size_t)lookup_group_size);
      if (groupLane < max_groupLane)
        own_key = csi_block_vals[i + groupLane];
      for (int j = 0; j < max_groupLane; j++) {
        T key = __shfl_sync(group_mask, own_key, j, lookup_group_size);
        // Get the cell id
        int globalCellId =
            HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
        int localCellId =
            CELL_LOCAL_ID(globalCellId, smId, sm_cell_block_length);
        int lookup_res =
            lookupBucketForTargetKey<T, bucket_cap, lookup_group_size,
                                     virtual_bucket_n>(
                key, data, bucket_n, globalCellId, localCellId, cells,
                cell_length, groupLane, group_mask, rand_seed);
        if (j == groupLane)
          own_res = lookup_res;
      }
      if (groupLane < max_groupLane) {
        csi_results[i + groupLane] = (own_res != 0);
      }
    }
#else
    // if (groupLane == 0)printf("for i = %d; i < %lu-%lu; i += %d\n",
    // groupId, sm_end_ptr, sm_ptr, groupN);
    for (int i = groupId; i < sm_end_ptr - sm_ptr; i += groupN) {
      // Get the key
      T key;
      if (groupLane == 0)
        key = csi_block_vals[sm_ptr + i];
      key = __shfl_sync(group_mask, key, 0, lookup_group_size);
      // Get the cell id
      int globalCellId =
          HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
      int localCellId = CELL_LOCAL_ID(globalCellId, smId, sm_cell_block_length);
      int lookup_res =
          lookupBucketForTargetKey<T, bucket_cap, lookup_group_size,
                                   virtual_bucket_n>(
              key, data, bucket_n, globalCellId, localCellId, cells,
              cell_length, groupLane, group_mask, rand_seed);
      if (groupLane == 0) { // laneId == 1 but not 0 because then there is
        // (laneId == 0) key = vals[i]?
        csi_results[sm_ptr + i] = (lookup_res != 0);
      }
    }
#endif
  }
}

template <typename T, int bucket_cap, int lookup_group_size,
          int virtual_bucket_n>
__global__ void GPHOSGPUTableLookupKeyReturnValueCSIKernel(
    const typename HalfTypeT<T>::HT *csi_block_keys,
    const size_t *csi_block_ptrs, const size_t *csi_block_end_ptrs,
    typename HalfTypeT<T>::HT *csi_results, T *const data, const int bucket_n,
    const CELL_T *cells, const int cell_length, const int rand_seed) {
  using HT = typename HalfTypeT<T>::HT;
  // compile-time const
  constexpr int TOTAL_TURN = bucket_cap / lookup_group_size;
  constexpr int KV_SIZE = sizeof(T);
  constexpr int VECTOR_LEN =
      (16 < (TOTAL_TURN * KV_SIZE) ? 16 : (TOTAL_TURN * KV_SIZE)) / KV_SIZE;
  using V = CUDAVectorType_t<T, VECTOR_LEN>;
  /*
      The data are stored in "data" in format of bucket, the bucket capibility
      is likely to be 32 or multiply of 32.
      The cells are firstly copied to shared memory.
      The warp is the unit to process the request, so every 32 threads are
     working together to handle one lookup in "vals".

      For a warp processing a request, they firstly get the cell by computing
     the hash1 of the request, then they get the cell offset (we can do this by
     one thread get the value and broadcast by __shfl_sync).

      Then use hash2 as the bucket function to transfer cell id j to bucket id,
      id(i) = (hash2((j<<10) | (i)) ) % bucket_n.

      Use hash3 to get the bucket i.
      bucket_i = (hash3(key) + offset) % virtual_bucket_n
      bucket_id = id(bucket_i)

      Get the bucket content, the warp works together to get the bucket with
     coalesced access.
  */
  // int idGlobal = threadIdx.x + blockIdx.x * blockDim.x;
  int groupLane =
      threadIdx.x % lookup_group_size; // groupLane is the serial in a group (a
                                       // group could be different from a warp)
  int groupId = threadIdx.x / lookup_group_size;
  int groupN = blockDim.x / lookup_group_size;
  int smId = blockIdx.x;
  unsigned group_mask = getWarpMask(lookup_group_size, threadIdx.x);
  int sm_cell_block_length = (int)ceil(cell_length * 1.0 / BLOCK_COUNT);

  // copy cells array to shared mem
#ifndef TEMP_CELL_IN_GLOBAL
  int copyId = threadIdx.x;

  extern __shared__ CELL_T shared[];
  while (copyId < sm_cell_block_length &&
         smId * sm_cell_block_length + copyId < cell_length) // cell_length
  {
    shared[copyId] = cells[smId * sm_cell_block_length + copyId];
    // printf("GPU msg\t==========\tshared[%d] = cells[%d * %d + %d]\n",
    // copyId, smId, sm_cell_block_length, copyId);
    copyId += blockDim.x;
  }
#endif

  size_t sm_ptr;
  size_t sm_end_ptr;
  if (groupLane == 0) {
    sm_ptr = csi_block_ptrs[smId];
    sm_end_ptr = csi_block_end_ptrs[smId];
  }
  sm_ptr = __shfl_sync(group_mask, sm_ptr, 0, lookup_group_size);
  sm_end_ptr = __shfl_sync(group_mask, sm_end_ptr, 0, lookup_group_size);

#ifdef NKPR
  size_t group_block_size = (size_t)ceil((sm_end_ptr - sm_ptr) * 1.0 / groupN);
  size_t group_start_ptr = sm_ptr + groupId * group_block_size;
  size_t group_end_ptr =
      min(sm_end_ptr, sm_ptr + (groupId + 1) * group_block_size);
#endif

  __syncthreads();
  // __threadfence_block();

  // each request is processed by a warp
  if (sm_ptr < sm_end_ptr) {
#ifdef NKPR
    for (int i = group_start_ptr; i < group_end_ptr; i += lookup_group_size) {
      HT own_key;
      HT own_res;
      int max_groupLane = min(group_end_ptr - i, (size_t)lookup_group_size);
      if (groupLane < max_groupLane)
        own_key = csi_block_keys[i + groupLane];
      for (int j = 0; j < max_groupLane; j++) {
        HT key = __shfl_sync(group_mask, own_key, j, lookup_group_size);
        // Get the cell id
        int globalCellId =
            HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
        int localCellId =
            CELL_LOCAL_ID(globalCellId, smId, sm_cell_block_length);
        HT lookup_res = lookupBucketForTargetKeyReturnValue<
            T, bucket_cap, lookup_group_size, virtual_bucket_n>(
            key, data, bucket_n, globalCellId, localCellId, cells, cell_length,
            groupLane, group_mask, rand_seed);
        if (j == groupLane)
          own_res = lookup_res;
      }
      if (groupLane < max_groupLane) {
        csi_results[i + groupLane] = own_res;
      }
    }
#else
    // if (groupLane == 0)printf("for i = %d; i < %lu-%lu; i += %d\n",
    // groupId, sm_end_ptr, sm_ptr, groupN);
    for (int i = groupId; i < sm_end_ptr - sm_ptr; i += groupN) {
      // Get the key
      HT key;
      if (groupLane == 0)
        key = csi_block_keys[sm_ptr + i];
      key = __shfl_sync(group_mask, key, 0, lookup_group_size);
      // Get the cell id
      int globalCellId =
          HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
      int localCellId = CELL_LOCAL_ID(globalCellId, smId, sm_cell_block_length);
      // printf("key %u globalCellId %d localCellId %d\n", key, globalCellId, localCellId);
      HT lookup_res =
          lookupBucketForTargetKeyReturnValue<T, bucket_cap, lookup_group_size,
                                              virtual_bucket_n>(
              key, data, bucket_n, globalCellId, localCellId, cells,
              cell_length, groupLane, group_mask, rand_seed);
      if (groupLane == 0) { // laneId == 1 but not 0 because then there is
        // (laneId == 0) key = vals[i]?
        csi_results[sm_ptr + i] = lookup_res;
      }
    }
#endif
  }
}

#endif

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
double GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                     virtual_bucket_n>::test_load_factor(int fail_limit,
                                                         int seed,
                                                         UnifiedTimeRecorder
                                                             *recorder) {
  using HT = typename HalfTypeT<T>::HT;

  int arr_n = _bucket_n * bucket_cap;
  HT *insert_arr = new HT[arr_n];
  HT *results = new HT[arr_n];
  HT *results_GPU = new HT[arr_n];

  T *packed_kv = new T[arr_n];

  T cur_elem = 0;
  for (int i = 0; i < arr_n; i++) {
    insert_arr[i] = ++cur_elem;
  }
  if (seed == -1)
    seed = time(0);
  std::shuffle(insert_arr, insert_arr + arr_n,
               std::default_random_engine(seed));

  for (int i = 0; i < arr_n; i++) {
    results[i] = insert_arr[i] + 1;
    packed_kv[i] = combineKV<T>(insert_arr[i], results[i]);
  }

  int R = arr_n;
  int L = 1000;
  int binary_search_round = 8;
  assert(R > L);

  int insert_batch_size = (R + L) / 2;
  while (binary_search_round-- > 0) {
    bool getlower = false;
    insert_key_values(packed_kv, insert_batch_size, nullptr);
    lookup_key_return_value_CSI(insert_arr, results_GPU, insert_batch_size,
                                nullptr);
    int error_cnt = 0;
    int valid_cnt = 0;
    for (int valid_i = 0; valid_i < insert_batch_size; valid_i++) {
      if (results_GPU[valid_i] != (insert_arr[valid_i] + 1)) {
        error_cnt++;
        if (error_cnt >= fail_limit) {
          getlower = true;
          break;
        }
      } else
        valid_cnt++;
    }
    clear();
    if (getlower) {
      vclog(INFO,
            "Test load factor: left round {}, insert {} kvs causes {} error "
            "(limit {}), get lower",
            binary_search_round, insert_batch_size, error_cnt, fail_limit);
      insert_batch_size = (L + insert_batch_size) / 2;
    } else {
      vclog(INFO,
            "Test load factor: left round {}, insert {} kvs causes {} error "
            "(limit {}), get higher",
            binary_search_round, insert_batch_size, error_cnt, fail_limit);
      insert_batch_size = (insert_batch_size + R) / 2;
    }
  }
  return insert_batch_size * 1.0 / arr_n;
}

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                   virtual_bucket_n>::show_content() const {
  show_content_kv(false);
}

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                   virtual_bucket_n>::show_content_kv(bool show_split_kv)
    const {
  using HT = typename HalfTypeT<T>::HT;
  int item_count = 0;
  fmt::print("USED_CELLS_ARRAY_LENGTH(_cells_length) "
             "{}\nACTUAL_CELLS_ARRAY_LENGTH(_cells_length) {}\n_bucket_n "
             "{}\nbucket_cap {}\nvirtual_bucket_n {}\n_rand_seed {}\n_size "
             "{}\nGPHOS_BLOCK_SIZE {}\n",
             USED_CELLS_ARRAY_LENGTH(_cells_length),
             ACTUAL_CELLS_ARRAY_LENGTH(_cells_length), _bucket_n, bucket_cap,
             virtual_bucket_n, _rand_seed, _size, GPHOS_BLOCK_SIZE);

  fmt::print("=========cell content==========\n");
  for (int i = 0; i < USED_CELLS_ARRAY_LENGTH(_cells_length); i++) {
    CELL_T cell_value = CELL_AT_I(_cells, i);
    CELL_T offset = GET_OFFSET_FROM_CELL(cell_value, virtual_bucket_n);
    CELL_T cvbid = GET_CVBID_FROM_CELL(cell_value, virtual_bucket_n);
    fmt::print("Cell {: <4} -> Bucket [", i);
    for (int vbi = 0; vbi < virtual_bucket_n; vbi++) {
      int bi = HASH_BUCKET_ID(i, vbi, virtual_bucket_n,
                              USED_CELLS_ARRAY_LENGTH(_cells_length), cvbid,
                              _bucket_n, _rand_seed);
      fmt::print("{: <4} ", bi);
    }

    fmt::print("] + offset: {}, cvbid: {}\n", offset, cvbid);
  }
  fmt::print("\n");

  fmt::print("=========buckets content(key, first-level cell)==========\n");
  for (int bi = 0; bi < _bucket_n; bi++) {
    fmt::print("B{: <4} ", bi);
    for (int ei = 0; ei < bucket_cap; ei++) {
      T elem = _data[bi * bucket_cap + ei];

      if (checkAllBitsSet(elem))
        fmt::print("{: <10}", "null");
      else {
        item_count += 1;
        if (show_split_kv) {
          HT key, value;
          splitKV(_data[bi * bucket_cap + ei], key, value);
          fmt::print("{: <10}", fmt::format("{}->{}", key, value));
        } else {
          fmt::print("{: <10}", _data[bi * bucket_cap + ei]);
        }
      }
    }
    fmt::print("\n");
    fmt::print("C{: <4} ", bi);
    for (int ei = 0; ei < bucket_cap; ei++) {
      if (_data[bi * bucket_cap + ei] == getAllBitsSet<T>()) {
        fmt::print("{: <10}", "null");
      } else {
        fmt::print("{: <10}",
                   HASH_CELL_ID(_data[bi * bucket_cap + ei], _rand_seed,
                                USED_CELLS_ARRAY_LENGTH(_cells_length)));
      }
    }
    fmt::print("\n");
    fmt::print("\n");
  }
  fmt::print("Item count in the table {}, load factor {}\n", item_count,
             item_count * 1.0 / (_bucket_n * bucket_cap));
  fmt::print("\n");
}

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                   virtual_bucket_n>::clear() {
  memset(_data, 0xff, (_bucket_n * bucket_cap) * sizeof(T));
  memset(_cells, 0, (_cells_length) * sizeof(CELL_T));
  _size = 0;
}

// // 3xx res means insert is not successful and need further processing
// #define INSERT_RES_LOCK_FAIL 300
// #define INSERT_RES_COMPLEX_INESRT 301
// #define INSERT_RES_CIRCULAR_MOVE_FAILD 302

// // 2xx res means insert succeed
// #define INSERT_RES_DIRECT_INSERT_SUCCESS 200
// #define INSERT_RES_CIRCULAR_MOVE_AND_INSERT_SUCCESS 201

// 1
#define GROUP_STAT_COOP (INSERT_THREAD_STAT_TYPE)0x100 // 0b0000000100000000
#define INSERT_THREAD_STAT_COOP_SUC                                            \
  (INSERT_THREAD_STAT_TYPE)0x101 // 0b0000000100000001
#define INSERT_THREAD_STAT_COOP_FAILD                                          \
  (INSERT_THREAD_STAT_TYPE)0x102 // 0b0000000100000010

// 2
#define GROUP_STAT_HOLD_KEY (INSERT_THREAD_STAT_TYPE)0x200 // 0b0000001000000000
#define INSERT_THREAD_STAT_HOLD_KEY                                            \
  (INSERT_THREAD_STAT_TYPE)0x201 // 0b0000001000000001
#define INSERT_THREAD_STAT_HOLD_KEY_ALLOW_COMPLEX                              \
  (INSERT_THREAD_STAT_TYPE)0x202 // 0b0000001000000010

// 3
#define GROUP_STAT_INSERT_SUC (INSERT_THREAD_STAT_TYPE)0x400
#define INSERT_THREAD_STAT_INIT (INSERT_THREAD_STAT_TYPE)0x401
#define INSERT_THREAD_STAT_DIRECT_INSERT_SUC (INSERT_THREAD_STAT_TYPE)0x402
#define INSERT_THREAD_STAT_CM_INSERT_SUC (INSERT_THREAD_STAT_TYPE)0x403
#define INSERT_THREAD_STAT_CVB_INSERT_SUC (INSERT_THREAD_STAT_TYPE)0x404

// 4
#define GROUP_STAT_DISCARD (INSERT_THREAD_STAT_TYPE)0x800
#define INSERT_THREAD_STAT_DISCARD (INSERT_THREAD_STAT_TYPE)0x801

// 5
#define GROUP_STAT_RESET_WHEN_DIFFICULT (INSERT_THREAD_STAT_TYPE)0x1000
#define INSERT_THREAD_STAT_POSSIBLE_COMPLEX (INSERT_THREAD_STAT_TYPE)0x1001

// 6
#define GROUP_STAT_RESET (INSERT_THREAD_STAT_TYPE)0x2000
#define INSERT_THREAD_STAT_LOCK_FAILD (INSERT_THREAD_STAT_TYPE)0x2001
#define INSERT_THREAD_STAT_CM_KILLED (INSERT_THREAD_STAT_TYPE)0x2002

// 7
#define GROUP_STAT_WAIT_LEADER (INSERT_THREAD_STAT_TYPE)0x4000
#define INSERT_THREAD_STAT_CM_BLOCKED (INSERT_THREAD_STAT_TYPE)0x4001

// 8
#define GROUP_STAT_ALL_COMPLETE (INSERT_THREAD_STAT_TYPE)0x8000
#define INSERT_THREAD_STAT_ALL_COMPLETE (INSERT_THREAD_STAT_TYPE)0x8001

#define IS_GET_KEY_AT_START_OF_GROUP_ROUND(stat)                               \
  ((stat & (GROUP_STAT_INSERT_SUC | GROUP_STAT_DISCARD)) != 0)
#define MUST_BE_ELIGIBLE_LEADER(stat) ((stat & GROUP_STAT_HOLD_KEY) != 0)
#define LEADER_TRY_DIRECT_INSERT(stat) ((stat & GROUP_STAT_HOLD_KEY) != 0)
#define LEADER_CONTINUE_CM(stat) ((stat == INSERT_THREAD_STAT_CM_BLOCKED))
#define LEADER_INSERT_TYPE(stat)                                               \
  (LEADER_TRY_DIRECT_INSERT(stat) ? 0 : (LEADER_CONTINUE_CM(stat) ? 1 : 2))
#define WAIT_TO_BE_LEADER(stat) ((stat & GROUP_STAT_WAIT_LEADER) != 0)
#define WAIT_TO_BE_RESET(stat) ((stat & GROUP_STAT_RESET) != 0)
#define RESET_WHEN_DIFFICULT(stat)                                             \
  ((stat & GROUP_STAT_RESET_WHEN_DIFFICULT) != 0)
#define IS_SUCCESS(stat)                                                       \
  ((stat == INSERT_THREAD_STAT_COOP_SUC) ||                                    \
   ((stat & GROUP_STAT_INSERT_SUC) != 0))
#define IS_ALL_COMPLETE(stat) ((stat == INSERT_THREAD_STAT_ALL_COMPLETE))

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ inline int
scanBucketForEmptySlot(T *const data, const int bucketId, const int groupLane,
                       const int group_mask, int &target) {
  constexpr int accessTurn = bucket_cap / insert_group_size;
  int warpLaneEmptySlot;
#ifdef DISABLE_VECTORIZATION_AND_INSTRUCTION_PARALLEL
  T slot;
  bool emptySlotFound = false;
#pragma unroll
  for (int t = 0; t < accessTurn; t++) {
    slot = BUCKET_I_ELEMENT_J(data, bucketId,
                              SLOT(groupLane, insert_group_size, t, accessTurn),
                              bucket_cap);
    if (checkAllBitsSet(slot)) {
      emptySlotFound = true;
      target = t;
    }
    warpLaneEmptySlot =
        ballotLowestWarpLaneIdWithTrue(emptySlotFound, group_mask);
    if (warpLaneEmptySlot >= 0)
      break;
  }

#else
  T slots[accessTurn];
#pragma unroll
  for (int t = 0; t < accessTurn; t++) {
    slots[t] = BUCKET_I_ELEMENT_J(
        data, bucketId, SLOT(groupLane, insert_group_size, t, accessTurn),
        bucket_cap);
  }

  bool emptySlotFound = false;

#pragma unroll
  for (int t = 0; t < accessTurn; t++) {
    if (checkAllBitsSet(slots[t])) {
      emptySlotFound = true;
      target = t;
    }
  }

  warpLaneEmptySlot =
      ballotLowestWarpLaneIdWithTrue(emptySlotFound, group_mask);
#endif
  return warpLaneEmptySlot;
}

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ INSERT_THREAD_STAT_TYPE circularMoveGPU(
    T key, LOCK_T *const bucket_locks, LOCK_T *const cell_read_counter,
    LOCK_T *const cell_read_locks, LOCK_T *const cell_global_locks,
    T *const data, const int bucket_n, CELL_T *const cells,
    const int cell_length, const int rand_seed, const int threadN,
    const int groupLane, const int group_mask, const bool isCooperativeLane,
    ComplexInsertProcessingStatus
        &complexInsertStatus, // never change this if you are cooperative lane
    GROUP_ROUND_CNT_TYPE &wait_until_group_round, // never change this if you
                                                  // are cooperative lane
    GROUP_ROUND_CNT_TYPE current_group_round,
    const bool isContinuing, // true if cm is restored from being blocked,
    const uint8_t max_overflow_handle_level) {
  /***
   Return status: SUCCESS, BLOCKED, KILLED, FAILED
   if not isContinuing: access glock (spin); register queueId

   access virtual bucket locks one by one
   if killed: release glock and return KILLED

  */
  INSERT_THREAD_STAT_TYPE res;
  res = isCooperativeLane ? INSERT_THREAD_STAT_COOP_FAILD
                          : INSERT_THREAD_STAT_DISCARD;
  if (!isCooperativeLane)
    DEVICE_PRINTF("debug circularMoveGPU start, discarded key %d.\n", key);
  return res;
}

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ INSERT_THREAD_STAT_TYPE putKeyIntoBucket(
    T key, LOCK_T *const bucket_locks, LOCK_T *const cell_read_counter,
    LOCK_T *const cell_read_locks, LOCK_T *const cell_global_locks,
    T *const data, const int bucket_n, CELL_T *const cells,
    const int cell_length, const int rand_seed, const bool allowComplexInsert,
    const int threadN, const int groupLane, const int group_mask,
    const bool isCooperativeLane,
    ComplexInsertProcessingStatus
        &complexInsertStatus, // never change this if you are cooperative lane
    GROUP_ROUND_CNT_TYPE &
        wait_until_group_round, // never change this if you are cooperative lane
    GROUP_ROUND_CNT_TYPE current_group_round, const bool enable_rwlock,
    const uint8_t max_overflow_handle_level) {
  // caculate the cell id
  INSERT_THREAD_STAT_TYPE res;
  int cellId =
      HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));

  // only thread 0 do the lock work
  // R/W lock the cell array
  // spin access the read lock (light lock)

  bool cell_lock_get_success =
      enable_rwlock ? rwLockBeginRead(groupLane, group_mask, insert_group_size,
                                      cell_read_counter + cellId,
                                      cell_read_locks + cellId,
                                      cell_global_locks + cellId, threadN)
                    : true;
  bool noEmptySlotFound = false;
  if (cell_lock_get_success) {
    // access the cell offset
    CELL_T cell_value;
    if (groupLane == 0) {
      cell_value = CELL_AT_I(cells, cellId);
    }
    cell_value = __shfl_sync(group_mask, cell_value, 0, insert_group_size);
    CELL_T offset = GET_OFFSET_FROM_CELL(cell_value, virtual_bucket_n);
    CELL_T cvbid = GET_CVBID_FROM_CELL(cell_value, virtual_bucket_n);

    int bucketSerial = HASH_BUCKET_S(key, rand_seed, offset, virtual_bucket_n);
    int bucketId = HASH_BUCKET_ID(cellId, bucketSerial, virtual_bucket_n,
                                  USED_CELLS_ARRAY_LENGTH(cell_length), cvbid,
                                  bucket_n, rand_seed);

    // request for bucket lock in lock-free manner
    bool bucket_lock_request_res = lockFreeRequest(
        groupLane, group_mask, insert_group_size, bucket_locks + bucketId);

    // if request is failed, return INSERT_RES_LOCK_FAIL
    if (bucket_lock_request_res) {
      // each thread reserves bucket_cap/group_size registers for reading
      // the bucket slots
      constexpr int accessTurn = bucket_cap / insert_group_size;
      __syncwarp(group_mask);
      int target;
      int warpLaneEmptySlot =
          scanBucketForEmptySlot<T, bucket_cap, insert_group_size,
                                 virtual_bucket_n>(data, bucketId, groupLane,
                                                   group_mask, target);
      if (warpLaneEmptySlot >= 0) {
        if (groupLane == (warpLaneEmptySlot % insert_group_size)) {
          BUCKET_I_ELEMENT_J(
              data, bucketId,
              SLOT(groupLane, insert_group_size, target, accessTurn),
              bucket_cap) = key;
        }
        res = isCooperativeLane ? INSERT_THREAD_STAT_COOP_SUC
                                : INSERT_THREAD_STAT_DIRECT_INSERT_SUC;
      } else {
        noEmptySlotFound = true;
      }
      __threadfence();
      lockRelease(groupLane, bucket_locks + bucketId);
    } else {
      // if not access bucket lock
      res = isCooperativeLane ? INSERT_THREAD_STAT_COOP_FAILD
                              : INSERT_THREAD_STAT_LOCK_FAILD;
      if (!isCooperativeLane) {
        wait_until_group_round = current_group_round + 1;
      }
    }
  } else {
    // if not get the rw lock of cell
    res = isCooperativeLane ? INSERT_THREAD_STAT_COOP_FAILD
                            : INSERT_THREAD_STAT_LOCK_FAILD;
    if (!isCooperativeLane) {
      wait_until_group_round = current_group_round + 1;
    }
  }

  if (enable_rwlock)
    rwLockEndRead(groupLane, cell_read_counter + cellId,
                  cell_read_locks + cellId, cell_global_locks + cellId,
                  threadN);
  // DEVICE_PRINTF("key %d res %d\n", key, res);

  if (noEmptySlotFound) {
    // no empty slot found in the bucket
    if (max_overflow_handle_level == ONLY_DIRECT_INSERT) {
      res = isCooperativeLane ? INSERT_THREAD_STAT_COOP_FAILD
                              : INSERT_THREAD_STAT_DISCARD;
    } else if (max_overflow_handle_level >= ALLOW_CIRCULAR_MOVE) {
      if (allowComplexInsert) {
        // if complex insert is allowed, cm is started from here
        res =
            circularMoveGPU<T, bucket_cap, insert_group_size, virtual_bucket_n>(
                key, bucket_locks, cell_read_counter, cell_read_locks,
                cell_global_locks, data, bucket_n, cells, cell_length,
                rand_seed, threadN, groupLane, group_mask, isCooperativeLane,
                complexInsertStatus, wait_until_group_round,
                current_group_round, false, max_overflow_handle_level);
      } else {
        res = isCooperativeLane ? INSERT_THREAD_STAT_COOP_FAILD
                                : INSERT_THREAD_STAT_POSSIBLE_COMPLEX;
      }
      // do not include cvb here, cvb can only be started from a failed cm,
      // if cvb get blocked, it should be discussed in the scheduler but
      // not here
    }
  }
  return res;
}

/**
NOTE: This implementation does not use shared memory to store cell array, so it
is capable with large cell array.

The insert cooperative group (ICG) is the unit to handle insert instructions,
and the number of threads in each ICG is specified in arguments.
* Note: to support multi-group to handle complex insert is to be discussed.

const bool delete_inserted_key_in_vals: if the key is inserted successfully, delete the key from vals
const bool enable_delay_complex_insert: if true, when direct insert failed because of full bucket, complex insert will not be triggered immediately, but will be triggered if there is no successful insert in the last group round.
const bool enable_rwlock: set rwlock for cells, to avoid the cell value be changed during read.
const uint8_t max_overflow_handle_level: complex insert that exceed the this level will lead to the discard of the key.



TODO:
Consider the construct function (different from insert, construct means build
from none) to split insert kernel to two kernels, the first kernels can assume
all cell arrays equal to zero, so we may avoid read cell in global memory and
do not need to lock cell.

*/
template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__global__ void GPHOSGPUTableInsertValsKernel(
    T *const vals, const int n, LOCK_T *const bucket_locks,
    LOCK_T *const cell_read_counter, LOCK_T *const cell_read_locks,
    LOCK_T *const cell_global_locks, T *const data, const int bucket_n,
    CELL_T *const cells, const int cell_length, const int rand_seed,
    const bool delete_inserted_key_in_vals,
    const bool enable_delay_complex_insert, const bool enable_rwlock,
    const uint8_t max_overflow_handle_level) {
  // group size smaller than 32 may cause dead lock in spin-locking in
  // pre-volta architecture. assert(group_size == 32);

  assert(insert_group_size <= bucket_cap);

  // PART I, insert group:
  /**
   * Group as a unit.
   * A group handle one insert key in a round.
   * A group round is {group_size} rounds.
   * At the very beginning, each thread in the group read a key from val.
   * In each round, one thread will be the leader and lead the group to insert
   * its key. The leader is selected in round-robin order. If a thread find its
   * insert could be complex insert, then it is skipped in this group round,
   * but it still holds its key. If a thread cannot access the lock, then it is
   * skipped in this group round.
   *
   * After a group round, the threads that have sucessfully insert its key read
   * the next key. Or if all threads complete the insertion, they immediately
   * read next key.
   *
   * If at the end of a group round, no direct insert occurs during the group
   * round, then the group round start again, and this time complex insert is
   * allowed.
   */

  /**
   * thread-level constants
   */
  const int idGlobal = threadIdx.x + blockIdx.x * blockDim.x;
  const int threadN = gridDim.x * blockDim.x;
  // const int groupId = idGlobal / insert_group_size;
  const int groupLane = idGlobal % insert_group_size;
  // const int warpLane = idGlobal % warpSize;
  // const int groupN = blockDim.x * gridDim.x / insert_group_size;
  const unsigned group_mask = getWarpMask(insert_group_size, threadIdx.x);

  int nxtPos = idGlobal;
  T own_key;

  INSERT_THREAD_STAT_TYPE thread_stat = INSERT_THREAD_STAT_INIT;
  GROUP_ROUND_CNT_TYPE wait_until_group_round = 0;
  GROUP_ROUND_CNT_TYPE current_group_round = 0;
  bool difficult_to_succeed = false;
  ComplexInsertProcessingStatus complexInsertStatus;
  complexInsertStatus.nxt_virtual_bucket_lock = 0;
  complexInsertStatus.queue_id = 0;

  // group round
  while (true) {
    ++current_group_round;

    if (IS_GET_KEY_AT_START_OF_GROUP_ROUND(thread_stat)) {
      if (nxtPos < n) {
        own_key = vals[nxtPos];
        nxtPos += threadN;
        thread_stat = (enable_delay_complex_insert)
                          ? (INSERT_THREAD_STAT_HOLD_KEY)
                          : (INSERT_THREAD_STAT_HOLD_KEY_ALLOW_COMPLEX);
      } else {
        thread_stat = INSERT_THREAD_STAT_ALL_COMPLETE;
      }
    }

    if (checkAllBitsSet<T>(own_key)) {
      thread_stat = INSERT_THREAD_STAT_DISCARD;
    }

    // waiting thread will not be permitted be leader
    bool not_waiting = (wait_until_group_round <= current_group_round);
    if (WAIT_TO_BE_RESET(thread_stat) && not_waiting) {
      thread_stat = (enable_delay_complex_insert)
                        ? (INSERT_THREAD_STAT_HOLD_KEY)
                        : (INSERT_THREAD_STAT_HOLD_KEY_ALLOW_COMPLEX);
    }

    if (RESET_WHEN_DIFFICULT(thread_stat) && difficult_to_succeed) {
      thread_stat = INSERT_THREAD_STAT_HOLD_KEY_ALLOW_COMPLEX;
    }

    bool anyDirectInsertSuccess = false;
    // round
    for (int r = 0; r < insert_group_size; r++) {
      bool canBeLeader = (MUST_BE_ELIGIBLE_LEADER(thread_stat) ||
                          (WAIT_TO_BE_LEADER(thread_stat) && not_waiting));
      // select the leader
      int leaderWarpLane =
          ballotLowestWarpLaneIdWithTrue(canBeLeader, group_mask);

      // if no leader available, immediately start next group round.
      if (leaderWarpLane >= 0) {
        int leaderGroupLane = leaderWarpLane % insert_group_size;
        bool isCooperativeLane = (leaderGroupLane != groupLane);

        // sync the leader key, leaderWarpLane > [0, group_size-1] is
        // okay, which is equivalent to leaderWarpLane % group_size
        T key = __shfl_sync(group_mask, own_key, leaderGroupLane,
                            insert_group_size);
        int leaderInsertType =
            __shfl_sync(group_mask, LEADER_INSERT_TYPE(thread_stat),
                        leaderGroupLane, insert_group_size);
        bool allow_complex_insert_this_round = __shfl_sync(
            group_mask,
            thread_stat == INSERT_THREAD_STAT_HOLD_KEY_ALLOW_COMPLEX,
            leaderGroupLane, insert_group_size);

        // if insert fails (lock fail or complex insert)
        INSERT_THREAD_STAT_TYPE insertResult;
        if (leaderInsertType == 0) {
          insertResult = putKeyIntoBucket<T, bucket_cap, insert_group_size,
                                          virtual_bucket_n>(
              key, bucket_locks, cell_read_counter, cell_read_locks,
              cell_global_locks, data, bucket_n, cells, cell_length, rand_seed,
              allow_complex_insert_this_round, threadN, groupLane, group_mask,
              isCooperativeLane, complexInsertStatus, wait_until_group_round,
              current_group_round, enable_rwlock, max_overflow_handle_level);
        } else if (leaderInsertType == 1) {
          // continue CM
          insertResult = circularMoveGPU<T, bucket_cap, insert_group_size,
                                         virtual_bucket_n>(
              key, bucket_locks, cell_read_counter, cell_read_locks,
              cell_global_locks, data, bucket_n, cells, cell_length, rand_seed,
              threadN, groupLane, group_mask, isCooperativeLane,
              complexInsertStatus, wait_until_group_round, current_group_round,
              true, max_overflow_handle_level);
        } else {
          // TODO
        }

        // if no direct insert success in a group round, then next round
        // we allow complex insert to occur.
        if (!anyDirectInsertSuccess) {
          anyDirectInsertSuccess = IS_SUCCESS(insertResult);
        }

        // update the thread stat according to the insert result
        if (!isCooperativeLane) {
          thread_stat = insertResult;
        }
      } else {
        break;
      }
      __syncwarp(group_mask);
    }
    if (enable_delay_complex_insert) {
      difficult_to_succeed = !anyDirectInsertSuccess;
    }

    if (delete_inserted_key_in_vals && IS_SUCCESS(thread_stat)) {
      vals[nxtPos - threadN] = getAllBitsSet<T>();
    }

    // __syncwarp(group_mask);
    // if all threads in group have allComplete true, mission accomplished.
    if (__all_sync(group_mask, INSERT_THREAD_STAT_ALL_COMPLETE == thread_stat))
      break;

    // debug only
    if (current_group_round > (GROUP_ROUND_CNT_TYPE)n * 1000) {
      printf("ERROR: TOO MANY ROUND, stat code %02x %d\n", thread_stat,
             thread_stat == INSERT_THREAD_STAT_ALL_COMPLETE);
      break;
    }
  }
}

/**
* About 2 insert stages:
* We want to avoid unneccessary global access as much as possible, so our strategy is to let direct insert 
* to be as quick as possible and also be prioritized, and the complex insert could endure more global access
* since they are already costy. 
* So in the first insert stage, we do not require direct insert to write back result, but insert failure need 
* to write false to insert result.
* So stage 1: dont_insert_already_succeed=false; write_back_insert_result=1; allow_complex_insert=false;
*    stage 2: dont_insert_already_succeed=true;  write_back_insert_result=0; allow_complex_insert=true; 
  &  initialize insert_result to be all true
*/

#define DIRECT_INSERT_RES_SUC 0
#define DIRECT_INSERT_RES_BKT_FULL 1
#define DIRECT_INSERT_RES_LOCK_FAILD 2

#define EXT_MOVE_RES_SUC 0
#define EXT_MOVE_RES_FAILD 1
#define EXT_MOVE_RES_PENDING_SHORT 2
#define EXT_MOVE_RES_PENDING_LONG 3

// __device__ void init_ComplexInsertProcessingStatus(ComplexInsertProcessingStatus &CVBStatus) {
//   // how to describe the status of a CVB, and which steps could CVB be interrupted
//   // 1. CVBGroupID
//   // 2. old_cvbid, new_cvbid (Cell[id] -> cvbid | offset)
//   // 3. old_cvbs_lock_progress
//   // 4. new_cvbs_lock_progress
//   // printf("Not implemented");
// }

// // template <typename T, int bucket_cap, int insert_group_size,
// //           int virtual_bucket_n>
// // __global__ void
// // simplifiedGPHOSGPUTableInsertValsKernel(
// //     T *const vals, const int n,
// //     LOCK_T *const bucket_locks,
// //     // LOCK_T *const cell_locks,
// //     T *const data, const int bucket_n,
// //     CELL_T *const cells, const int cell_length, const int rand_seed,
// //     bool *const insert_result,
// //     const bool dont_insert_already_succeed, // if true, then read insert result and only insert false ones.
// //     const int write_back_insert_result, // 0 for not write back, 1 for write false for failed, 2 for write true for succeed.
// //     const bool allow_complex_insert
// // )
// // {
// //   /**
// //   * asserts before start
// //   */
// //   assert(insert_group_size <= bucket_cap);

// //   /**
// //    * thread-level constants
// //    */
// //   const int idGlobal = threadIdx.x + blockIdx.x * blockDim.x;
// //   const int threadN = gridDim.x * blockDim.x;
// //   // const int groupId = idGlobal / insert_group_size;
// //   const int groupLane = idGlobal % insert_group_size;
// //   // const int warpLane = idGlobal % warpSize;
// //   // const int groupN = blockDim.x * gridDim.x / insert_group_size;
// //   const unsigned group_mask = getWarpMask(insert_group_size, threadIdx.x);
// //   bool *insert_result_write_back_position = nullptr;

// //    /**
// //    * Insert group member status initialized
// //    */
// //   int nxtPos = idGlobal;
// //   T own_key;
// //   InsertGroupMemberStatus status;
// //   status.isHoldingkey = false;
// //   status.isComplete = false;
// //   status.isExtMove = false;
// //   status.isPending = false;
// //   status.pendingUntilGroupRound = 0;

// //   /**
// //   * CVB status initialized
// //   */
// //   ComplexInsertProcessingStatus cvbStatus;

// //   /**
// //   * Group Round
// //   */
// //   GROUP_ROUND_CNT_TYPE current_group_round = 0;
// //   while(true) {
// //     ++current_group_round;

// //     /**
// //     * if dont_insert_already_succeed is true, read insert_result[nxtPos] to check whether next key to read should be skipped.
// //     */
// //     bool skip_read_next_key = false;
// //     if (nxtPos < n && dont_insert_already_succeed) {
// //       skip_read_next_key = insert_result[nxtPos];
// //     }

// //     /**
// //     * handle pending threads
// //     */
// //     if (status.isPending) {
// //       status.isPending = (status.pendingUntilGroupRound > current_group_round);
// //     }

// //     /**
// //     * Get key, if you dont have key and not completed
// //     */
// //     if (!status.isHoldingkey && !status.isComplete) {
// //       if (nxtPos < n) {
// //         if (!skip_read_next_key) {
// //           own_key = vals[nxtPos];
// //           insert_result_write_back_position = &(insert_result[nxtPos]);
// //           status.isHoldingkey = true;
// //         }
// //         nxtPos += threadN;
// //       }
// //       else {
// //         status.isComplete = true;
// //       }
// //     }

// //     /**
// //     * Each group round contains $insert_group_size$ turns.
// //     */
// //     for (int turn = 0; turn < insert_group_size; turn++) {
// //       /**
// //       * Elect the leader. The thread who is holding a key and not pending can be elected to a leader.
// //       */
// //       bool canBeLeader = (status.isHoldingkey && !status.isPending && !status.isComplete);
// //       int leaderWarpLane = ballotLowestWarpLaneIdWithTrue(canBeLeader, group_mask);

// //       if (leaderWarpLane >= 0) {
// //         int leaderGroupLane = leaderWarpLane % insert_group_size;
// //         bool isLeader = (leaderGroupLane == groupLane);

// //         T key = __shfl_sync(group_mask, own_key, leaderGroupLane, insert_group_size);

// //         bool isLeaderCVBing = __shfl_sync(group_mask, status.isCVBing, leaderGroupLane, insert_group_size);
// //         if ((!allow_complex_insert) || (!isLeaderCVBing)) {
// //           /**
// //           * Try to direct insert
// //           */
// //           int direct_insert_res = simplifiedPutKeyIntoBucket<T, bucket_cap, insert_group_size, virtual_bucket_n>(
// //                                                       key,
// //                                                       bucket_locks,
// //                                                       // cell_locks, // dont use rwlock, it is too expensive
// //                                                       data, bucket_n, cells,
// //                                                       cell_length, rand_seed,
// //                                                       threadN, groupLane, group_mask,
// //                                                       !isLeader,
// //                                                       false
// //                                                     );
// //           if (isLeader) {
// //             if (direct_insert_res == DIRECT_INSERT_RES_SUC) {
// //               // direct insert successful, not hold key now
// //               status.isHoldingkey = false;
// //               // printf("DEBUG: Insert %d SUCCESS.\n", key);

// //               // if write_back_insert_result is 2
// //               if (write_back_insert_result == 2) {
// //                 (*insert_result_write_back_position) = true;
// //               }
// //             }
// //             else if (direct_insert_res == DIRECT_INSERT_RES_BKT_FULL) {
// //               // bucket full, if allow_complex_insert is true, then set up CVB; allow_complex_insert is false, discard.
// //               if (allow_complex_insert) {
// //                 status.isCVBing = true;
// //                 // TODO setup CVB! Consider what is the status for CVB
// //                 init_ComplexInsertProcessingStatus(cvbStatus);
// //               }
// //               else {
// //                 // discard, if write_back_insert is 1
// //                 if (write_back_insert_result == 1) {
// //                   (*insert_result_write_back_position) = false;
// //                 }
// //                 status.isHoldingkey = false;
// //                 // printf("DEBUG: Insert %d DISCARD.\n", key);
// //               }
// //             }
// //             else if (direct_insert_res == DIRECT_INSERT_RES_LOCK_FAILD) {
// //               // direct insert lock failed, pending to next group round
// //               status.isPending = true;
// //               status.pendingUntilGroupRound = current_group_round + 1;
// //             }
// //             else {
// //               printf("Undefined behavior.\n");
// //             }
// //           }

// //         } else {
// //           /***
// //           * is CVBing, remember only leader do
// //           */
// //         }
// //       }
// //       else {
// //         /**
// //         * No thread is leader, end the group round immediately.
// //         */
// //         break;
// //       }
// //       __syncwarp(group_mask);
// //     }
// //     if (__all_sync(group_mask,status.isComplete == true))
// //       break;

// //     if (current_group_round > (GROUP_ROUND_CNT_TYPE)n * 1000)
// //     {
// //       printf("ERROR: TOO MANY ROUND, threadGlobalID %d, nxtPos %d, isComplete %d, isHoldKey %d, isCVB %d, isPending %d(%d)\n", idGlobal, nxtPos, status.isComplete,
// //         status.isHoldingkey, status.isCVBing, status.isPending, status.pendingUntilGroupRound);
// //       break;
// //     }
// //   }

// // }

/**
* Direct insert success: return 0
* Direct insert bucket full: return 1
* Lock access failed: return 2
*/
// template <typename T, int bucket_cap, int insert_group_size,
//           int virtual_bucket_n>
// __device__ int
// simplifiedPutKeyIntoBucket(
//     T key,
//     LOCK_T *const bucket_locks,
//     // LOCK_T *const cell_locks, // dont use rwlock, it is too expensive
//     T *const data, const int bucket_n, CELL_T *const cells,
//     const int cell_length, const int rand_seed,
//     const int threadN, const int groupLane, const int group_mask,
//     const bool isCooperativeLane,
//     const bool enable_cell_lock
//   )
// {
//   int insert_res;

//   int cellId = HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
//   CELL_T cell_value;
//   if (groupLane == 0)
//   {
//     cell_value = CELL_AT_I(cells, cellId);
//   }
//   cell_value = __shfl_sync(group_mask, cell_value, 0, insert_group_size);
//   CELL_T offset = GET_OFFSET_FROM_CELL(cell_value, virtual_bucket_n);
//   CELL_T cvbid = GET_CVBID_FROM_CELL(cell_value, virtual_bucket_n);

//   int bucketSerial = HASH_BUCKET_S(key, rand_seed, offset, virtual_bucket_n);
//   int bucketId = HASH_BUCKET_ID(cellId, bucketSerial, virtual_bucket_n, USED_CELLS_ARRAY_LENGTH(cell_length), cvbid,bucket_n, rand_seed);

//   bool bucket_lock_get = lockFreeRequest(groupLane, group_mask, insert_group_size, bucket_locks + bucketId);

//   if (bucket_lock_get) {
//     __syncwarp(group_mask);
//     constexpr int accessTurn = bucket_cap / insert_group_size;
//     int target;
//     int warpLaneEmptySlot = scanBucketForEmptySlot<T, bucket_cap, insert_group_size,virtual_bucket_n>
//                                                       (data, bucketId, groupLane, group_mask, target);
//     if (warpLaneEmptySlot >= 0) {
//       if (groupLane == (warpLaneEmptySlot % insert_group_size))
//       {
//         BUCKET_I_ELEMENT_J(
//             data, bucketId,
//             SLOT(groupLane, insert_group_size, target, accessTurn),
//             bucket_cap) = key;
//       }
//       insert_res = DIRECT_INSERT_RES_SUC;
//     }
//     else {
//       insert_res = DIRECT_INSERT_RES_BKT_FULL;
//     }
//     __syncwarp(group_mask);

//     __threadfence();
//     lockRelease(groupLane, bucket_locks + bucketId);
//   } else {
//     insert_res = DIRECT_INSERT_RES_LOCK_FAILD;
//   }
//   return insert_res;
// }

// template <typename T, int bucket_cap, int insert_group_size,
//           int virtual_bucket_n>
// __global__ void
// simplifiedGPHOSGPUTableInsertKeyValueKernel(
//     T* const kv_array, // type T is compacted, its first half is Key, second half is Value
//     const int n, //   kv_array length is n
//     LOCK_T *const bucket_locks,
//     T *const data, const int bucket_n,
//     CELL_T *const cells, const int cell_length, const int rand_seed,
//     bool *const insert_result,
//     const bool dont_insert_already_succeed, // if true, then read insert result and only insert false ones.
//     const int write_back_insert_result, // 0 for not write back, 1 for write false for failed, 2 for write true for succeed.
//     const bool allow_complex_insert
// )
// {
//   /**
//   * asserts before start
//   */
//   assert(insert_group_size <= bucket_cap);

//   /**
//    * thread-level constants
//    */
//   const int idGlobal = threadIdx.x + blockIdx.x * blockDim.x;
//   const int threadN = gridDim.x * blockDim.x;
//   // const int groupId = idGlobal / insert_group_size;
//   const int groupLane = idGlobal % insert_group_size;
//   // const int warpLane = idGlobal % warpSize;
//   // const int groupN = blockDim.x * gridDim.x / insert_group_size;
//   const unsigned group_mask = getWarpMask(insert_group_size, threadIdx.x);
//   bool *insert_result_write_back_position = nullptr;

//   // printf("This is thread %d\n", idGlobal);
//    /**
//    * Insert group member status initialized
//    */
//   int nxtPos = idGlobal;
//   T own_kv;

//   InsertGroupMemberStatus status;
//   status.isHoldingkey = false;
//   status.isComplete = false;
//   status.isCVBing = false;
//   status.isPending = false;
//   status.pendingUntilGroupRound = 0;

//   /**
//   * CVB status initialized
//   */
//   ComplexInsertProcessingStatus cvbStatus;

//   /**
//   * Group Round
//   */
//   GROUP_ROUND_CNT_TYPE current_group_round = 0;
//   while(true) {
//     ++current_group_round;

//     /**
//     * if dont_insert_already_succeed is true, read insert_result[nxtPos] to check whether next key to read should be skipped.
//     */
//     bool skip_read_next_key = false;
//     if (nxtPos < n && dont_insert_already_succeed) {
//       skip_read_next_key = insert_result[nxtPos];
//     }

//     /**
//     * handle pending threads
//     */
//     if (status.isPending) {
//       status.isPending = (status.pendingUntilGroupRound > current_group_round);
//     }

//     /**
//     * Get key, if you dont have key and not completed
//     */
//     if (!status.isHoldingkey && !status.isComplete) {
//       if (nxtPos < n) {
//         if (!skip_read_next_key) {
//           own_kv = kv_array[nxtPos];
//           insert_result_write_back_position = &(insert_result[nxtPos]);
//           status.isHoldingkey = true;
//         }
//         nxtPos += threadN;
//       }
//       else {
//         status.isComplete = true;
//       }
//     }

//     /**
//     * Each group round contains $insert_group_size$ turns.
//     */
//     for (int turn = 0; turn < insert_group_size; turn++) {
//       /**
//       * Elect the leader. The thread who is holding a key and not pending can be elected to a leader.
//       */
//       bool canBeLeader = (status.isHoldingkey && !status.isPending && !status.isComplete);
//       int leaderWarpLane = ballotLowestWarpLaneIdWithTrue(canBeLeader, group_mask);

//       if (leaderWarpLane >= 0) {
//         int leaderGroupLane = leaderWarpLane % insert_group_size;
//         bool isLeader = (leaderGroupLane == groupLane);

//         T kv = __shfl_sync(group_mask, own_kv, leaderGroupLane, insert_group_size);

//         bool isLeaderCVBing = __shfl_sync(group_mask, status.isCVBing, leaderGroupLane, insert_group_size);
//         if ((!allow_complex_insert) || (!isLeaderCVBing)) {
//           /**
//           * Try to direct insert
//           */
//           int direct_insert_res = simplifiedPutKeyValueIntoBucket<T, bucket_cap, insert_group_size, virtual_bucket_n>(
//                                                       kv,
//                                                       bucket_locks,
//                                                       data, bucket_n, cells,
//                                                       cell_length, rand_seed,
//                                                       threadN, groupLane, group_mask,
//                                                       !isLeader,
//                                                       false
//                                                     );
//           if (isLeader) {
//             if (direct_insert_res == DIRECT_INSERT_RES_SUC) {
//               // direct insert successful, not hold key now
//               status.isHoldingkey = false;
//               // printf("DEBUG: Insert %d SUCCESS.\n", key);

//               // if write_back_insert_result is 2
//               if (write_back_insert_result == 2) {
//                 (*insert_result_write_back_position) = true;
//               }
//             }
//             else if (direct_insert_res == DIRECT_INSERT_RES_BKT_FULL) {
//               // bucket full, if allow_complex_insert is true, then set up CVB; allow_complex_insert is false, discard.
//               if (allow_complex_insert) {
//                 status.isCVBing = true;
//                 // TODO setup CVB! Consider what is the status for CVB
//                 init_ComplexInsertProcessingStatus(cvbStatus);
//               }
//               else {
//                 // discard, if write_back_insert is 1
//                 if (write_back_insert_result == 1) {
//                   (*insert_result_write_back_position) = false;
//                 }
//                 status.isHoldingkey = false;
//                 // printf("DEBUG: Insert %d DISCARD.\n", key);
//               }
//             }
//             else if (direct_insert_res == DIRECT_INSERT_RES_LOCK_FAILD) {
//               // direct insert lock failed, pending to next group round
//               status.isPending = true;
//               status.pendingUntilGroupRound = current_group_round + 1;
//             }
//             else {
//               printf("Undefined behavior.\n");
//             }
//           }

//         } else {
//           /***
//           * is CVBing, remember only leader do
//           */
//         }
//       }
//       else {
//         /**
//         * No thread is leader, end the group round immediately.
//         */
//         break;
//       }
//       __syncwarp(group_mask);
//     }
//     if (__all_sync(group_mask,status.isComplete == true))
//       break;

//     if (current_group_round > (GROUP_ROUND_CNT_TYPE)n * 1000)
//     {
//       printf("ERROR: TOO MANY ROUND, threadGlobalID %d, nxtPos %d, isComplete %d, isHoldKey %d, isCVB %d, isPending %d(%d)\n", idGlobal, nxtPos, status.isComplete,
//         status.isHoldingkey, status.isCVBing, status.isPending, status.pendingUntilGroupRound);
//       break;
//     }
//   }
// }

/**
* Direct insert success: return 0
* Direct insert bucket full: return 1
* Lock access failed: return 2
// */
// template <typename T, int bucket_cap, int insert_group_size,
//           int virtual_bucket_n>
// __device__ int
// simplifiedPutKeyValueIntoBucket(
//     T kv,
//     LOCK_T *const bucket_locks,
//     // LOCK_T *const cell_locks, // dont use rwlock, it is too expensive
//     T *const data, const int bucket_n, CELL_T *const cells,
//     const int cell_length, const int rand_seed,
//     const int threadN, const int groupLane, const int group_mask,
//     const bool isCooperativeLane,
//     const bool enable_cell_lock
//   )
// {
//   using HT = typename HalfTypeT<T>::HT;
//   HT key, value;
//   splitKV(kv, key, value);

//   int insert_res;

//   int cellId = HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
//   CELL_T cell_value;
//   if (groupLane == 0)
//   {
//     cell_value = CELL_AT_I(cells, cellId);
//   }
//   cell_value = __shfl_sync(group_mask, cell_value, 0, insert_group_size);
//   CELL_T offset = GET_OFFSET_FROM_CELL(cell_value, virtual_bucket_n);
//   CELL_T cvbid = GET_CVBID_FROM_CELL(cell_value, virtual_bucket_n);

//   int bucketSerial = HASH_BUCKET_S(key, rand_seed, offset, virtual_bucket_n);
//   int bucketId = HASH_BUCKET_ID(cellId, bucketSerial, virtual_bucket_n, USED_CELLS_ARRAY_LENGTH(cell_length), cvbid, bucket_n, rand_seed);

//   bool bucket_lock_get = lockFreeRequest(groupLane, group_mask, insert_group_size, bucket_locks + bucketId);

//   if (bucket_lock_get) {
//     __syncwarp(group_mask);
//     constexpr int accessTurn = bucket_cap / insert_group_size;
//     int target;
//     int warpLaneEmptySlot = scanBucketForEmptySlot<T, bucket_cap, insert_group_size,virtual_bucket_n>
//                                                       (data, bucketId, groupLane, group_mask, target);
//     if (warpLaneEmptySlot >= 0) {
//       if (groupLane == (warpLaneEmptySlot % insert_group_size))
//       {
//         BUCKET_I_ELEMENT_J(
//             data, bucketId,
//             SLOT(groupLane, insert_group_size, target, accessTurn),
//             bucket_cap) = kv;
//       }
//       insert_res = DIRECT_INSERT_RES_SUC;
//     }
//     else {
//       insert_res = DIRECT_INSERT_RES_BKT_FULL;
//     }
//     __syncwarp(group_mask);

//     __threadfence();
//     lockRelease(groupLane, bucket_locks + bucketId);
//   } else {
//     insert_res = DIRECT_INSERT_RES_LOCK_FAILD;
//   }
//   return insert_res;
// }

#include "dionlyphase.cuh"
#include "remainingphase.cuh"

#include "excsi.cuh"