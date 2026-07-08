// functions (mainly GPU functions declerations)
#pragma once

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__host__ void
GPHOSGPUTableInsertValsCPU(const T *const vals, const int n, int *size,
                              T *const data, const int bucket_n,
                              CELL_T *cells, const int cell_length,
                              const int rand_seed, const int fail_limit);

template <typename T, int bucket_cap, int lookup_group_size,
          int virtual_bucket_n>
__global__ void
GPHOSGPUTableLookupValsKernel(const T *const vals, bool *const results,
                                 const int n, T *const data,
                                 const int bucket_n, const CELL_T *cells,
                                 const int cell_length, const int rand_seed);

#ifdef CROSS_SM_INDEX
template <typename T, int bucket_cap, int lookup_group_size,
          int virtual_bucket_n>
__global__ void GPHOSGPUTableLookupValsCSIKernel(
    const T *csi_block_vals, const size_t *csi_block_ptrs,
    const size_t *csi_block_end_ptrs, bool *csi_results, T *const data,
    const int bucket_n, const CELL_T *cells, const int cell_length,
    const int rand_seed);


template <typename T, int bucket_cap, int lookup_group_size,
int virtual_bucket_n>
__global__ void
GPHOSGPUTableLookupKeyReturnValueCSIKernel(const typename HalfTypeT<T>::HT *csi_block_keys,
                              const size_t *csi_block_ptrs,
                              const size_t *csi_block_end_ptrs,
                              typename HalfTypeT<T>::HT *csi_results, T *const data,
                              const int bucket_n, const CELL_T *cells,
                              const int cell_length,
                              const int rand_seed);

#endif

__host__ size_t
getL2MaxPersistenceSizeInBytes()
{
  int device_id;
  cudaGetDevice(&device_id);
  cudaDeviceProp prop;
  cudaGetDeviceProperties(&prop, device_id);
  return (size_t)(prop.persistingL2CacheMaxSize * SETASIDE_L2_PERCENTAGE);
}

#define V100S
__host__ size_t
getSharedMemoryPerBlockSizeInBytes()
{
#ifdef V100S
  return 96 * 1024;
#else
  int device_id;
  cudaGetDevice(&device_id);
  cudaDeviceProp prop;
  cudaGetDeviceProperties(&prop, device_id);
  return prop.sharedMemPerBlock;
#endif
}

__host__ int
getMaxThreadsPerBlock()
{
  int device_id;
  cudaGetDevice(&device_id);
  cudaDeviceProp prop;
  cudaGetDeviceProperties(&prop, device_id);
  return prop.maxThreadsPerBlock;
}

__host__ int
getMultiProcessorCount()
{
  int device_id;
  cudaGetDevice(&device_id);
  cudaDeviceProp prop;
  cudaGetDeviceProperties(&prop, device_id);
  return prop.multiProcessorCount;
}

__host__ size_t
getAvailableFastMemorySizeInBytes()
{
  size_t fast_memory_size = 0;
  fast_memory_size += SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE;

#ifdef L2_AS_FAST_MEMORY
  fast_memory_size += getL2MaxPersistenceSizeInBytes();
#endif
  return fast_memory_size;
}

inline __device__ CELL_T cell_at_i_gpu(const CELL_T *_cells_shared,
                                       const CELL_T *_cells_l2, int i);

typedef uint16_t INSERT_THREAD_STAT_TYPE;
typedef uint64_t GROUP_ROUND_CNT_TYPE;
typedef uint64_t COMPLEX_INSERT_GROUP_QUEUE_ID_TYPE;
typedef struct
{
  int nxt_virtual_bucket_lock; // nxt virtual bucket to access lock,
  COMPLEX_INSERT_GROUP_QUEUE_ID_TYPE queue_id; // if queue_id == 0, not during complex insert; >0
} ComplexInsertProcessingStatus;


typedef uint8_t EXT_MOVE_STEP;

typedef struct {
  EXT_MOVE_STEP step;
  unsigned long long group_rank;
  int next_this_bucket_lock_to_access;
  int next_that_bucket_lock_to_access;
  CELL_T expected_cvbid;
  size_t this_workspace_id;
  size_t that_workspace_id;
  CELL_T cell_value;
} ExtMoveStatus;


typedef struct
{
  GROUP_ROUND_CNT_TYPE pendingUntilGroupRound;
  bool isHoldingkey;
  bool isComplete;
  bool isPending;
  bool isExtMove;
  ExtMoveStatus extState;
} InsertGroupMemberStatus;

__device__ void initExtMoveStatus(InsertGroupMemberStatus& status) {
  status.extState.step = 0; 
  status.extState.group_rank = 0; 
  status.extState.next_this_bucket_lock_to_access = 0; 
  status.extState.next_that_bucket_lock_to_access = 0; 
  status.extState.expected_cvbid = 0; 
  status.extState.this_workspace_id = 0; 
  status.extState.that_workspace_id = 0; 
  status.extState.cell_value = 0;
}

__device__ void initInsertGroupMemberStatus(InsertGroupMemberStatus& status) {
  status.pendingUntilGroupRound = 0;
  status.isHoldingkey = false;
  status.isComplete = false;
  status.isPending = false;
  status.isExtMove = false;
  initExtMoveStatus(status);
}

__device__ void setPending(InsertGroupMemberStatus& status, GROUP_ROUND_CNT_TYPE pendingRound, GROUP_ROUND_CNT_TYPE current_round) {
  status.pendingUntilGroupRound = current_round + pendingRound;
  status.isPending = true;
}

__device__ void syncExtMoveStatus(ExtMoveStatus &newExtMoveStatus, InsertGroupMemberStatus& status, const int groupLane, const int leaderLane, const int group_mask, int insert_group_size) {
  newExtMoveStatus.step = __shfl_sync(group_mask, status.extState.step, leaderLane, insert_group_size);
  newExtMoveStatus.group_rank = __shfl_sync(group_mask, status.extState.group_rank, leaderLane, insert_group_size);
  newExtMoveStatus.next_this_bucket_lock_to_access = __shfl_sync(group_mask, status.extState.next_this_bucket_lock_to_access, leaderLane, insert_group_size);
  newExtMoveStatus.next_that_bucket_lock_to_access = __shfl_sync(group_mask, status.extState.next_that_bucket_lock_to_access, leaderLane, insert_group_size);
  newExtMoveStatus.expected_cvbid = __shfl_sync(group_mask, status.extState.expected_cvbid, leaderLane, insert_group_size);
  newExtMoveStatus.this_workspace_id = __shfl_sync(group_mask, status.extState.this_workspace_id, leaderLane, insert_group_size);
  newExtMoveStatus.that_workspace_id = __shfl_sync(group_mask, status.extState.that_workspace_id, leaderLane, insert_group_size);
  newExtMoveStatus.cell_value = __shfl_sync(group_mask, status.extState.cell_value, leaderLane, insert_group_size);
}

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__global__ void GPHOSGPUTableInsertValsKernel(
    T *const vals, const int n, LOCK_T *const bucket_locks,
    LOCK_T *const cell_read_counter, LOCK_T *const cell_read_locks,
    LOCK_T *const cell_global_locks, T *const data, const int bucket_n,
    CELL_T *const cells, const int cell_length, const int rand_seed,
    const bool delete_inserted_key_in_vals,
    const bool enable_delay_complex_insert, const bool enable_rwlock,
    const uint8_t max_overflow_handle_level);

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
        &complexInsertStatus,                     // never change this if you are cooperative lane
    GROUP_ROUND_CNT_TYPE &wait_until_group_round, // never change this if you
                                                  // are cooperative lane
    GROUP_ROUND_CNT_TYPE current_group_round,
    const bool enable_rwlock, const uint8_t max_overflow_handle_level);



template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ INSERT_THREAD_STAT_TYPE circularMoveGPU(
    T key, LOCK_T *const bucket_locks, LOCK_T *const cell_read_counter,
    LOCK_T *const cell_read_locks, LOCK_T *const cell_global_locks,
    T *const data, const int bucket_n, CELL_T *const cells,
    const int cell_length, const int rand_seed, const int threadN,
    const int groupLane, const int group_mask, const bool isCooperativeLane,
    ComplexInsertProcessingStatus
        &complexInsertStatus,                     // never change this if you are cooperative lane
    GROUP_ROUND_CNT_TYPE &wait_until_group_round, // never change this if you
                                                  // are cooperative lane
    GROUP_ROUND_CNT_TYPE current_group_round,
    const bool isContinuing,                      // true if cm is restored from being blocked,
    const uint8_t max_overflow_handle_level);

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ inline int
scanBucketForEmptySlot(T *const data, const int bucketId, const int groupLane,
                       const int group_mask, int &target);

__device__ inline bool
lockFreeRequest(const int groupLane, const int group_mask,
                const int group_size, LOCK_T *const lock)
{
  bool res;
  __threadfence();
  if (groupLane == 0)
    res = (atomicCAS(lock, 0, 1) == 0);
  res = __shfl_sync(group_mask, res, 0, group_size);
  __threadfence();
  return res;
}

template <typename T>
__device__ inline bool
workspaceLockFreeRequest(const int groupLane, const int group_mask,
                const int group_size, T *const lock)
{
  bool res;
  __threadfence_block();
  if (groupLane == 0)
    res = (atomicCAS((unsigned long long *)lock, 0, 1) == 0);
  res = __shfl_sync(group_mask, res, 0, group_size);
  __threadfence_block();
  return res;
}

__device__  inline LOCK_T 
bucketLockRequest(const int groupLane, const int group_mask, const LOCK_T my_rank, 
  const int group_size, LOCK_T *const lock)
{
  LOCK_T res;
  __threadfence();
  if (groupLane == 0) {
    res = atomicCAS(lock, 0, my_rank);
  }
  res = __shfl_sync(group_mask, res, 0, group_size);
  __threadfence();
  return res;
}

__device__ inline void
lockRelease(const int groupLane, LOCK_T *const lock, const int workLane = 0)
{
  __threadfence();
  if (groupLane == workLane)
  {
    atomicExch(lock, (LOCK_T)0);
    // bool res = (atomicCAS(lock, 1, 0) == 1);
    // assert(res);
  }
  __threadfence();
}

template <typename T>
__device__ inline void
workspaceLockRelease(const int groupLane, T *const lock, const int workLane = 0)
{
  __threadfence_block();
  if (groupLane == workLane)
  {
    atomicExch((unsigned long long *)lock, (unsigned long long)0);
    // bool res = (atomicCAS(lock, 1, 0) == 1);
    // assert(res);
  }
  __threadfence_block();
}

/**
 * WARNING: CALL THIS IN WARP LEVEL
 * For a resouce that is locked by a R/W Lock, use this function before
 * beginning to read.
 *
 * If the return value is true, then the resource will not be modified before
 * calling rwLockEndRead(), and it does not block other read (only blocks
 * write).
 *
 * If the return value is false, then the resource may be modified.
 *
 * Whatever the return value is, always call rwLockEndRead() when you are done.
 */
__device__ inline bool
rwLockBeginRead(const int groupLane, const int group_mask,
                const int group_size, LOCK_T *const read_counter_addr,
                LOCK_T *const read_locks_addr,
                LOCK_T *const global_locks_addr, const int counter_upper)
{
  bool res = true;
  if (groupLane == 0)
  {
    while (atomicCAS(read_locks_addr, 0, 1) != 0)
      ;
    LOCK_T b = atomicInc(read_counter_addr, counter_upper);
    if (b == 0)
    {
      // try to access the global lock, if fail, then give up
      LOCK_T global_lock = atomicCAS(global_locks_addr, 0, 1);
      if (global_lock != 0)
      {
        res = false;
      }
      // __threadfence();
    }
    while (atomicCAS(read_locks_addr, 1, 0) != 1)
      ;
  }
  res = __shfl_sync(group_mask, res, 0, group_size);
  return res;
}

/**
 * WARNING: CALL THIS IN WARP LEVEL
 * Always call rwLockEndRead() when you are done.
 */
__device__ inline void
rwLockEndRead(const int groupLane, LOCK_T *const read_counter_addr,
              LOCK_T *const read_locks_addr, LOCK_T *const global_locks_addr,
              const int counter_upper)
{
  if (groupLane == 0)
  {
    while (atomicCAS(read_locks_addr, 0, 1) != 0)
      ;
    LOCK_T b = atomicDec(read_counter_addr, counter_upper);
    if (b == 1)
    {
      // try to access the global lock, if fail, then give up
      LOCK_T global_lock = atomicCAS(global_locks_addr, 1, 0);
      if (global_lock != 1)
      {
        // impossible
        assert(false);
      }
      // __threadfence();  // may discuss whether it is necessary
    }
    while (atomicCAS(read_locks_addr, 1, 0) != 1)
      ;
  }
}

/**
 * Return the Warp Lane Id that is the lowest thread with pred==true.
 * Return -1 if no thread is pred==true.
 */
__device__ inline int
ballotLowestWarpLaneIdWithTrue(bool pred, int group_mask)
{
  int maskLeader = __ballot_sync(group_mask, pred) & group_mask;
  return __ffs(maskLeader & (-maskLeader)) - 1;
}

inline __device__ CELL_T
cell_at_i_gpu(const CELL_T *_cells_shared, const CELL_T *_cells_l2, int i)
{
  int shared_cell_length = SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE / sizeof(CELL_T);
  if (i < shared_cell_length)
  {
    return CELL_AT_I(_cells_shared, i);
  }
  else
  {
    return _cells_l2[i - shared_cell_length];
  }
}

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__host__ int circularMoveCPU(T key, int cellId, T *const data, int *data_size,
                             const int bucket_n, CELL_T *cells,
                             const int cell_length, const int rand_seed);

template <typename T, int bucket_cap, int lookup_group_size,
          int virtual_bucket_n>
__device__ inline int lookupBucketForTargetKey(
    const T key, T *const data, const int bucket_n, const int globalCellId,
    const int localCellId, const CELL_T *cells, const int cell_length,
    const int groupLane, const unsigned group_mask, const int rand_seed);


template <typename T, int bucket_cap, int lookup_group_size,
int virtual_bucket_n>
__device__ inline typename HalfTypeT<T>::HT
lookupBucketForTargetKeyReturnValue(const typename HalfTypeT<T>::HT key, T *const data, const int bucket_n,
                   const int globalCellId, const int localCellId,
                   const CELL_T *cells, const int cell_length,
                   const int groupLane, const unsigned group_mask,
                   const int rand_seed);

// template <typename T, int bucket_cap, int insert_group_size,
// int virtual_bucket_n>
// __device__ int
// simplifiedPutKeyIntoBucket(
//   T key, 
//   LOCK_T *const bucket_locks, 
//   // LOCK_T *const cell_locks, // dont use rwlock, it is too expensive
//   T *const data, const int bucket_n, CELL_T *const cells,
//   const int cell_length, const int rand_seed,
//   const int threadN, const int groupLane, const int group_mask,
//   const bool isCooperativeLane,
//   const bool enable_cell_lock
// );

// template <typename T, int bucket_cap, int insert_group_size,
//           int virtual_bucket_n>
// __global__ void
// simplifiedGPHOSGPUTableInsertValsKernel(
//     T *const vals, const int n, 
//     LOCK_T *const bucket_locks,
//     // LOCK_T *const cell_locks, 
//     T *const data, const int bucket_n,
//     CELL_T *const cells, const int cell_length, const int rand_seed,
//     bool *const insert_result,
//     const bool dont_insert_already_succeed, // if true, then read insert result and only insert false ones.
//     const int write_back_insert_result, // 0 for not write back, 1 for write false for failed, 2 for write true for succeed. 
//     const bool allow_complex_insert
// );


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
// );

// template <typename T, int bucket_cap, int insert_group_size,
//           int virtual_bucket_n>
// __device__ int
// simplifiedPutKeyValueIntoBucket(
//     T kv,
//     LOCK_T *const bucket_locks, 
//     T *const data, const int bucket_n, CELL_T *const cells,
//     const int cell_length, const int rand_seed,
//     const int threadN, const int groupLane, const int group_mask,
//     const bool isCooperativeLane,
//     const bool enable_cell_lock
// );

template <typename HT>
__global__ void adjust_EXCSI(
  HT *keys, size_t key_n,
  HT *regions, size_t regions_n,
  size_t keys_per_pre_block,
  size_t compress_num,
  size_t shared_mem_per_block_bytes,
  size_t region_len,
  size_t subregion_len,
  const int rand_seed,
  const int cell_length,
  const int sm_cell_block_length
);

template <typename T, int bucket_cap, int lookup_group_size,
          int virtual_bucket_n>
__global__ void
GPHOSGPUTableLookupKeyReturnValueEXCSIKernel(const typename HalfTypeT<T>::HT * regions,
                                    typename HalfTypeT<T>::HT * res_regions,
                                    size_t total_regions_len,
                                    size_t compress_num, 
                                    size_t region_len, size_t region_num,
                                    size_t subregion_len,
                                    T *const data,
                                    const int bucket_n, const CELL_T *cells,
                                    const int cell_length,
                                    const int rand_seed);



template <typename T, int bucket_cap, int insert_group_size,
int virtual_bucket_n>
__global__ void
DIOnlyInsertKeyValueKernel(
    T* const kv_array, // type T is compacted, its first half is Key, second half is Value
    const int n, //   kv_array length is n
    LOCK_T *const bucket_locks,
    T *const data, const int bucket_n,
    CELL_T *const cells, const int cell_length, const int rand_seed,
    bool *const insert_result
);

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ int
DIOnlyPutKeyValueIntoBucket(
    T kv,
    T *const data, const int bucket_n, CELL_T *const cells,
    const int cell_length, const int rand_seed,
    const int threadN, const int groupLane, const int group_mask
);

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__global__ void
RemainingPhaseInsertKeyValueKernel(
    T* const kv_array, // type T is compacted, its first half is Key, second half is Value
    const int n, //   kv_array length is n
    
    LOCK_T *const bucket_locks,
    LOCK_T *const cell_locks,
    LOCK_T *const group_rank_counter,
    size_t total_workspaces_size, 

    T *const data, const int bucket_n,
    CELL_T *const cells, const int cell_length, const int rand_seed,
    bool *const insert_result
);

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ int
RemainingPhaseExtendedMove(
    T kv,
    LOCK_T *const bucket_locks, 
    LOCK_T *const cell_locks, 
    LOCK_T *const group_rank_counter,
    size_t total_workspaces_size,
    T *const data, const int bucket_n, CELL_T *const cells,
    const int cell_length, const int rand_seed,
    const int threadN, const int groupLane, const int group_mask,
    ExtMoveStatus& extState,
    int current_group_round,
    const int group_id
  );

template <typename T, int bucket_cap, int insert_group_size,
int virtual_bucket_n>
__device__ void transferCircularMoveBucketInWorkspace(
  int fromBucket_i, bool fromIsBuffer,
  int toBucket_i,
  size_t workspace_id,
  int thisCellId,
  T kv, bool kvIsInTransfer,
  const int cell_length, const int rand_seed,
  const int groupLane, const int group_mask);

template <typename T, int bucket_cap, int insert_group_size,
int virtual_bucket_n>
__device__ void setupWorkspaceKthBucket(
  size_t workspace_id,
  int cellId, int bucketId, int vbid,
  T *const data, const int cell_length, const int rand_seed,
  const int groupLane, const int group_mask);

template <typename T, int bucket_cap, int insert_group_size,
int virtual_bucket_n>
__device__ void writeWorkspaceKthBucketBackToGlobalBucket(
  size_t workspace_id, int bucket_i,
  T* globalBucket,
  const int groupLane, const int group_mask);

template <typename T, int bucket_cap, int insert_group_size,
int virtual_bucket_n>
__device__ int
RemainingPhaseDirectInsertPutKeyValueIntoBucket(
  T kv,
  LOCK_T *const bucket_locks, 
  LOCK_T *const cell_locks, 
  T *const data, const int bucket_n, CELL_T *const cells,
  const int cell_length, const int rand_seed,
  const int threadN, const int groupLane, const int group_mask
);

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ void DirectlyInsertBucketInWorkspace(
    int toBucket_i,
    size_t workspace_id,
    int thisCellId,
    T kv, 
    const int cell_length, const int rand_seed,
    const int groupLane, const int group_mask);