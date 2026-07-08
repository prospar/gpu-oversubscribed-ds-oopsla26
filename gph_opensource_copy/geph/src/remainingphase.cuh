#pragma once
#include <limits>
#include "workspace.cuh"


#define MAX_ROUDN_FACTOR_N 1
// #define EXT_MOVE_DEBUG
#ifdef EXT_MOVE_DEBUG

#define CUDA_DEBUG_PRINTF(fmt, ...) printf(fmt, __VA_ARGS__)
#define IS_DEBUG_GROUP() if (blockIdx.x == 0 && threadIdx.x < 16)
#define CUDA_GROUP_DEBUG_PRINTF(fmt, ...) if (blockIdx.x == 0 && threadIdx.x < 16) CUDA_DEBUG_PRINTF("[%d]\t" fmt "\n", threadIdx.x, __VA_ARGS__); 
#define EARLY_RETURN() {CUDA_GROUP_DEBUG_PRINTF("Early Break. Bye Bye!\n",0); return;}
#define EARLY_RETURN_m() {CUDA_GROUP_DEBUG_PRINTF("Early Break. Bye Bye!\n",0); return -1;}
#define DEBUG_ASSERT(condition) assert(condition)

#else 

#define CUDA_DEBUG_PRINTF(fmt, ...)
#define IS_DEBUG_GROUP() 
#define CUDA_GROUP_DEBUG_PRINTF(fmt, ...)
#define EARLY_RETURN() {  }
#define EARLY_RETURN_m() {  }
#define DEBUG_ASSERT(condition)

#endif


__device__ bool checkBucketTransferValid(int fromBucketThisCellSlotCount, int toBucketEmptySlotCount, int toBucketThisCellCount) {
    return (fromBucketThisCellSlotCount <= (toBucketEmptySlotCount + toBucketThisCellCount));
}

template <typename T>
__device__ bool isBelongsToThisCell(T& kv, int thisCellId, const int cell_length, const int rand_seed){
    using HT = typename HalfTypeT<T>::HT;
    HT copykey, copyvalue;
    splitKV(kv, copykey, copyvalue);
    int copycellId = HASH_CELL_ID(copykey, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
    return (copycellId == thisCellId);
}

/***
* If you are using capability >= 8.0, please use reduce_or_sync
*/
__device__  unsigned int dirty_reduce_or_sync(const unsigned group_mask, int group_size, int groupLane, unsigned int value) {
    unsigned int res = 0;
    for (int i = 0; i < group_size; i++) {
        res |= __shfl_sync(group_mask, value, i, group_size);
    } 
    __syncwarp(group_mask);
    return res;
}


/**
* Return how many 1s are before the pos-th (start from 0) bit. If pos-th bit is 0, return -1.
*/
__device__ int isRthOneBit(unsigned int x, unsigned pos) {
    if ((x & (1U << pos)) == 0) {
        return -1; 
    }
    return __popc(x & ((1U << pos) - 1)); 
}

/***
* Returns the position (start from 0) in x that is 1 and there are r 1s before it. If not found, returns 0xffffffff.
*/ 
__device__ unsigned getRthOneBitPos(unsigned int x, int r) {
    return __fns(x, 0, r+1);
}


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
)
{  
  /**
  * asserts before start
  */
  assert(insert_group_size <= bucket_cap);

  /**
   * thread-level constants
   */
  CUDA_GROUP_DEBUG_PRINTF("hello, we have get started...",0);

  const int idGlobal = threadIdx.x + blockIdx.x * blockDim.x;
  const int threadN = gridDim.x * blockDim.x;
  const int groupId = idGlobal / insert_group_size;
  const int groupLane = idGlobal % insert_group_size;
  // const int warpLane = idGlobal % warpSize;
  // const int groupN = blockDim.x * gridDim.x / insert_group_size;
  const unsigned group_mask = getWarpMask(insert_group_size, threadIdx.x);
  
    if (idGlobal == 0) {
        (*group_rank_counter) = (LOCK_T)10;
    }
    extern __shared__ T sharedInsert[];
    for (int i = threadIdx.x; i < total_workspaces_size / sizeof(T); i += blockDim.x) {
        if (i < total_workspaces_size / sizeof(T)) {
            sharedInsert[i] = (T)0; // Initialize to zero
        }
    }
    

    __syncthreads();
  
  size_t insert_result_write_back_position = 0;

   /**
   * Insert group member status initialized
   */
  int nxtPos = idGlobal;
  T own_kv;

  InsertGroupMemberStatus status;
  initInsertGroupMemberStatus(status);

  CUDA_GROUP_DEBUG_PRINTF("PUGR %d, holdkey %d, comp %d, pend %d, ext %d", status.pendingUntilGroupRound, status.isHoldingkey, status.isComplete, status.isPending, status.isExtMove);
  /**
  * Group Round
  */
  GROUP_ROUND_CNT_TYPE current_group_round = 0;
  
  while(true) {
    current_group_round++;
    CUDA_GROUP_DEBUG_PRINTF("Group Round %llu", current_group_round);
    
    /**
    * handle pending threads
    */
    if (status.isPending) {
      status.isPending = (status.pendingUntilGroupRound > current_group_round);
    }

    /**
    * Get key, if you dont have key and not completed
    */
    if (!status.isHoldingkey && !status.isComplete) {
      while (true) {
        if (nxtPos >= n) {
            CUDA_GROUP_DEBUG_PRINTF("Complete, nxtPos %d >= n %d", nxtPos, n);
            status.isComplete = true;
            break;
        }
        if (!insert_result[nxtPos]) {
            own_kv = kv_array[nxtPos];
            insert_result_write_back_position = nxtPos;
            status.isHoldingkey = true;
            nxtPos += threadN;
            break;
        } else {
            nxtPos += threadN;
        }
      }
    }
    __syncwarp(group_mask);

    CUDA_GROUP_DEBUG_PRINTF("PUGR %llu, holdkey %d, comp %d, pend %d, ext %d", status.pendingUntilGroupRound, status.isHoldingkey, status.isComplete, status.isPending, status.isExtMove);
    
    // if (current_group_round >= (GROUP_ROUND_CNT_TYPE)100) {
    //     EARLY_RETURN();
    // }
    /**
    * Each group round contains $insert_group_size$ turns.
    */ 
    for (int turn = 0; turn < insert_group_size; turn++) {
      /**
      * Elect the leader. The thread who is holding a key and not pending can be elected to a leader.
      */
      bool canBeLeader = (status.isHoldingkey && !status.isExtMove && !status.isPending && !status.isComplete);
      int leaderWarpLane = ballotLowestWarpLaneIdWithTrue(canBeLeader, group_mask);
    
      CUDA_GROUP_DEBUG_PRINTF("Leader is lane %d", leaderWarpLane);

      if (leaderWarpLane < 0) {
        canBeLeader = (status.isHoldingkey && !status.isPending && !status.isComplete);
        leaderWarpLane = ballotLowestWarpLaneIdWithTrue(canBeLeader, group_mask);

        CUDA_GROUP_DEBUG_PRINTF("What? Have to be EXT? Well, leader is lane %d", leaderWarpLane);
      }

      if (leaderWarpLane >= 0) {
        int leaderGroupLane = leaderWarpLane % insert_group_size;
        bool isLeader = (leaderGroupLane == groupLane);
        
        T kv = __shfl_sync(group_mask, own_kv, leaderGroupLane, insert_group_size);

        // if (!isLeader) {
        //     assert(kv != own_kv);
        // }
        if (status.isComplete) {
            assert(!isLeader);
        }
        if (isLeader) {
            assert(status.isHoldingkey);
        }

        bool isLeaderExtMove = __shfl_sync(group_mask, status.isExtMove, leaderGroupLane, insert_group_size);
        if (isLeaderExtMove) {
            
            CUDA_GROUP_DEBUG_PRINTF("Lets EXT", 0);
            //Ext Move
            ExtMoveStatus extState;
            syncExtMoveStatus(extState, status, groupLane, leaderGroupLane, group_mask, insert_group_size);
            int extMoveRes = RemainingPhaseExtendedMove<T, bucket_cap, insert_group_size, virtual_bucket_n>(
                kv, bucket_locks, cell_locks, group_rank_counter, total_workspaces_size, 
                data, bucket_n, cells, cell_length, rand_seed, threadN, groupLane, group_mask, extState, current_group_round, groupId
            );
            
            CUDA_GROUP_DEBUG_PRINTF("EXT complete res %d", extMoveRes);
            if (isLeader) {
                status.extState = extState;
                assert(status.extState.group_rank > 0);
                assert(status.extState.step > 0);
                if (extMoveRes == EXT_MOVE_RES_SUC) {
                    status.isHoldingkey = false;
                    status.isExtMove = false;
                    insert_result[insert_result_write_back_position] = true;
                    initExtMoveStatus(status);

                    #ifdef EXT_MOVE_DEBUG
                    using HT = typename HalfTypeT<T>::HT;
                    HT key, value;
                    splitKV(kv, key, value);
                    printf("==================EXT_MOVE_RES_SUC, key %u\n", key);
                    #endif
                }
                else if (extMoveRes == EXT_MOVE_RES_FAILD) {
                    status.isHoldingkey = false;
                    status.isExtMove = false;
                    initExtMoveStatus(status);

                    #ifdef EXT_MOVE_DEBUG
                    using HT = typename HalfTypeT<T>::HT;
                    HT key, value;
                    splitKV(kv, key, value);
                    CUDA_GROUP_DEBUG_PRINTF("========%u,%u===ground %llu=======EXT_MOVE_RES_FAILD", key, value, current_group_round, extMoveRes);
                    #endif
                } 
                else if (extMoveRes == EXT_MOVE_RES_PENDING_SHORT) {
                    setPending(status, 1, current_group_round);
                    CUDA_GROUP_DEBUG_PRINTF("==================EXT_MOVE_RES_PENDING_SHORT", extMoveRes);

                    #ifdef EXT_MOVE_DEBUG
                    IS_DEBUG_GROUP(){
                        // DEBUG
                        CUDA_GROUP_DEBUG_PRINTF("CELL LOCK STATUS",0);
                        for (int i = 0; i < cell_length; i++) {
                            if (cell_locks[i] > 0) CUDA_GROUP_DEBUG_PRINTF("\t cell %d lock %u", i, cell_locks[i]);
                        }
                        CUDA_GROUP_DEBUG_PRINTF("BUCKET LOCK STATUS",0);
                        for (int i = 0; i < bucket_n; i++) { 
                            if (bucket_locks[i] > 0) CUDA_GROUP_DEBUG_PRINTF("\t bucket %d lock %u", i, bucket_locks[i]);
                        }
                    }
                    #endif
                } 
                else if (extMoveRes == EXT_MOVE_RES_PENDING_LONG) {
                    setPending(status, 3, current_group_round);
                    CUDA_GROUP_DEBUG_PRINTF("==================EXT_MOVE_RES_PENDING_LONG", extMoveRes);

                    #ifdef EXT_MOVE_DEBUG
                    IS_DEBUG_GROUP(){
                        // DEBUG
                        CUDA_GROUP_DEBUG_PRINTF("CELL LOCK STATUS",0);
                        for (int i = 0; i < cell_length; i++) {
                            if (cell_locks[i] > 0) CUDA_GROUP_DEBUG_PRINTF("\t cell %d lock %u", i, cell_locks[i]);
                        }
                        CUDA_GROUP_DEBUG_PRINTF("BUCKET LOCK STATUS",0);
                        for (int i = 0; i < bucket_n; i++) { 
                            if (bucket_locks[i] > 0) CUDA_GROUP_DEBUG_PRINTF("\t bucket %d lock %u", i, bucket_locks[i]);
                        }
                    }
                    #endif
                } 
                else {
                    #ifdef EXT_MOVE_DEBUG
                    printf("Undefined behavior with extMoveRes %d.\n", extMoveRes);
                    #endif
                }
            }
            CUDA_GROUP_DEBUG_PRINTF("PUGR %llu, holdkey %d, comp %d, pend %d, ext %d", status.pendingUntilGroupRound, status.isHoldingkey, status.isComplete, status.isPending, status.isExtMove);
            
        } 
        else {
            CUDA_GROUP_DEBUG_PRINTF("LETS direct insert",0);
            // direct insert 
            int direct_insert_res = RemainingPhaseDirectInsertPutKeyValueIntoBucket<T, bucket_cap, insert_group_size, virtual_bucket_n>(kv,
                        bucket_locks, cell_locks,
                        data, bucket_n, cells,
                        cell_length, rand_seed,
                        threadN, groupLane, group_mask
                    );
            
            CUDA_GROUP_DEBUG_PRINTF("direct insert complete res %d", direct_insert_res);
            if (isLeader) {
                if (direct_insert_res == DIRECT_INSERT_RES_SUC) {
                    status.isHoldingkey = false;
                    insert_result[insert_result_write_back_position] = true;

                    #ifdef EXT_MOVE_DEBUG
                    using HT = typename HalfTypeT<T>::HT;
                    HT key, value;
                    splitKV(kv, key, value);
                    printf("==================DIRECT_INSERT_RES_SUC, key %u\n", key);
                    #endif
                } 
                else if (direct_insert_res == DIRECT_INSERT_RES_BKT_FULL) {
                    status.isExtMove = true;
                    setPending(status, 1, current_group_round);
                    CUDA_GROUP_DEBUG_PRINTF("===============DIRECT_INSERT_RES_BKT_FULL", direct_insert_res);
                }
                else if (direct_insert_res == DIRECT_INSERT_RES_LOCK_FAILD) {
                    setPending(status, 1, current_group_round);
                    CUDA_GROUP_DEBUG_PRINTF("d===============DIRECT_INSERT_RES_LOCK_FAILD", direct_insert_res);
                    #ifdef EXT_MOVE_DEBUG
                    IS_DEBUG_GROUP(){
                        // DEBUG
                        CUDA_GROUP_DEBUG_PRINTF("CELL LOCK STATUS",0);
                        for (int i = 0; i < cell_length; i++) {
                            if (cell_locks[i] > 0) CUDA_GROUP_DEBUG_PRINTF("\t cell %d lock %u", i, cell_locks[i]);
                        }
                        CUDA_GROUP_DEBUG_PRINTF("BUCKET LOCK STATUS",0);
                        for (int i = 0; i < bucket_n; i++) { 
                            if (bucket_locks[i] > 0) CUDA_GROUP_DEBUG_PRINTF("\t bucket %d lock %u", i, bucket_locks[i]);
                        }
                    }
                    #endif
                }
                else {
                    #ifdef EXT_MOVE_DEBUG
                    printf("Undefined behavior direct_insert_res %d.\n", direct_insert_res);
                    #endif
                    assert(false);
                }
            }    
            CUDA_GROUP_DEBUG_PRINTF("PUGR %llu, holdkey %d, comp %d, pend %d, ext %d", status.pendingUntilGroupRound, status.isHoldingkey, status.isComplete, status.isPending, status.isExtMove);
        }
      } 
      else {
        break;
      }
      __syncwarp(group_mask);
    }
    if (__all_sync(group_mask,status.isComplete == true)) {
        break;
    }

    #ifdef EXT_MOVE_DEBUG
    if (current_group_round % (n / 10) == 1) {
        CUDA_GROUP_DEBUG_PRINTF("pendto %llu, holdkey %d, comp %d, pend %d, ext %d\n\tEXT step %u, rank %llu, nxtIB %d, nxtAB %d, EXCVB %u, IW %u, AW %u, CELL %u", status.pendingUntilGroupRound, status.isHoldingkey, status.isComplete, status.isPending, status.isExtMove, status.extState.step, status.extState.group_rank, status.extState.next_this_bucket_lock_to_access, status.extState.next_that_bucket_lock_to_access, status.extState.expected_cvbid, status.extState.this_workspace_id, status.extState.that_workspace_id, status.extState.cell_value);
    }
    #endif
      
    if (current_group_round % (n / 10) == 1) {
        if (idGlobal == 0) {
            printf("Already run for %d\n", current_group_round);
        }
    }

    if (current_group_round > (GROUP_ROUND_CNT_TYPE)n * MAX_ROUDN_FACTOR_N) {
        if (idGlobal == 0) {
            printf("WARNING: too many round, auto break.\n");
        }
        break;
    }

    if (current_group_round > (GROUP_ROUND_CNT_TYPE)n * 10)
    {
      printf("ERROR!: TOO MANY ROUND, auto break; threadGlobalID %d, nxtPos %d, isComplete %d, isHoldKey %d, isExtMove %d, isPending %d(to round %d)\n", idGlobal, nxtPos, status.isComplete,
        status.isHoldingkey, status.isExtMove, status.isPending, status.pendingUntilGroupRound);
      assert(false);
      break;
    }
  }

  __syncthreads();
}


/**
* Extended Move successfully avoid bucket overflow: 0
* Unable to find valid cellk to avoid bucket overflow: 1
*/ 
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
  )
{   
    int total_workspaces_number = TOTAL_WORKSPACES_NUMBER(total_workspaces_size);
    // printf("total_workspace_number = %d, as total_workspaces_size %lu / WORKSPACE_SIZE %lu", total_workspaces_number, total_workspaces_size, WORKSPACE_SIZE);
    using HT = typename HalfTypeT<T>::HT;
    extern __shared__ T sharedInsert[];
    int insert_res = -1;


    // WARNING: anything put in the front will not be cached between rerun of the same extMove. Thus, make sure their value does not depend on any single step below.
    // The variable used among steps should be put into ExtMoveStatus
    // when set step backward, be careful to the member of extState, you may need to reinitialize parts of them.
    
    // reliable
    HT key, value;
    splitKV(kv, key, value);
    int cellId = HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));

    // unreliable
    CELL_T offset = GET_OFFSET_FROM_CELL(extState.cell_value, virtual_bucket_n);
    CELL_T cvbid = GET_CVBID_FROM_CELL(extState.cell_value, virtual_bucket_n);
    int bucketSerial = HASH_BUCKET_S(key, rand_seed, offset, virtual_bucket_n);

    bool shouldReleaseCellLock = false;
    bool shouldReleaseAllThisBucketLock = false;
    bool shouldReleaseAllThatBucketLock = false;



    // initilaize
    if (extState.step == 0) {
        if (groupLane == 0)
            extState.group_rank = atomicInc(group_rank_counter, ULLONG_MAX);
        extState.group_rank = __shfl_sync(group_mask, extState.group_rank, 0, insert_group_size);
        extState.step = 1;
        __threadfence();

        CUDA_GROUP_DEBUG_PRINTF("***************step 0 complete get rank %llu", extState.group_rank);
    }

    // accessing cell lock
    if (extState.step == 1) {
        bool cell_lock_get = lockFreeRequest(groupLane, group_mask, insert_group_size, cell_locks + cellId);
        if (cell_lock_get) {
            CELL_T cell_value;
            if (groupLane == 0)
            {
                cell_value = CELL_AT_I(cells, cellId);
            }
            cell_value = __shfl_sync(group_mask, cell_value, 0, insert_group_size);
            offset = GET_OFFSET_FROM_CELL(cell_value, virtual_bucket_n);
            cvbid = GET_CVBID_FROM_CELL(cell_value, virtual_bucket_n);
            extState.cell_value = cell_value;
            bucketSerial = HASH_BUCKET_S(key, rand_seed, offset, virtual_bucket_n);

            extState.step = 2;
            CUDA_GROUP_DEBUG_PRINTF("***************step 1 complete get cell lock %d", cellId);
        } else {
            insert_res = EXT_MOVE_RES_PENDING_SHORT;
        }
    }

    // accessing this bucket locks
    if (extState.step == 2) {
        for (int request_bucket_vbid = extState.next_this_bucket_lock_to_access; request_bucket_vbid < virtual_bucket_n; request_bucket_vbid++) {
            int bucketId = HASH_BUCKET_ID(cellId, request_bucket_vbid, virtual_bucket_n, USED_CELLS_ARRAY_LENGTH(cell_length), cvbid, bucket_n, rand_seed);
            LOCK_T old_value = bucketLockRequest(groupLane, group_mask, extState.group_rank, insert_group_size, bucket_locks + bucketId);
            // if old_value is 0 (not locked) 
            if (old_value == 0) {
                extState.next_this_bucket_lock_to_access++;
                CUDA_GROUP_DEBUG_PRINTF("***************step 2 get bucket lock %d", bucketId);
            }
            // if old_value is 1 (locked by direct insert) or locked by another younger ext group, i wait
            else if (old_value == 1 || old_value >= extState.group_rank) {
                // dont need to give up cell lock, be back very soon
                insert_res = EXT_MOVE_RES_PENDING_SHORT;
                extState.next_this_bucket_lock_to_access = request_bucket_vbid;
                // {
                //     for (int rvbid = 0; rvbid < extState.next_this_bucket_lock_to_access; rvbid++) {
                //         int rbucketId = HASH_BUCKET_ID(cellId, rvbid, virtual_bucket_n, USED_CELLS_ARRAY_LENGTH(cell_length), cvbid, bucket_n, rand_seed);
                //         lockRelease(groupLane, bucket_locks + rbucketId, 0);
                //     }
                //     __syncwarp(group_mask);
                //     lockRelease(groupLane, cell_locks + cellId);
                //     extState.step = 1;
                //     extState.next_this_bucket_lock_to_access = 0;
                // }
                break;
            }
            // if locked by another elder ext group, i die
            else if (old_value < extState.group_rank) {
                // release all accessed lock, back to step 1
                int turn = 0;
                while (turn * insert_group_size + groupLane < (request_bucket_vbid)) {
                    int hadBucketId = HASH_BUCKET_ID(cellId, turn * insert_group_size + groupLane, virtual_bucket_n, USED_CELLS_ARRAY_LENGTH(cell_length), cvbid, bucket_n, rand_seed);
                    lockRelease(groupLane, bucket_locks + hadBucketId, groupLane);
                    ++turn;
                } 
                // for (int rvbid = 0; rvbid < extState.next_this_bucket_lock_to_access; rvbid++) {
                //     int rbucketId = HASH_BUCKET_ID(cellId, rvbid, virtual_bucket_n, USED_CELLS_ARRAY_LENGTH(cell_length), cvbid, bucket_n, rand_seed);
                //     lockRelease(groupLane, bucket_locks + rbucketId, 0);
                // }
                __syncwarp(group_mask);
                lockRelease(groupLane, cell_locks + cellId);
                extState.step = 1;
                extState.next_this_bucket_lock_to_access = 0;
                // if you directly copy this to that bucket, be careful with ExtMove
                insert_res = EXT_MOVE_RES_PENDING_LONG;
                break;
            }
            else {
                // impossible
                assert(false);
            }
        }
        if (extState.next_this_bucket_lock_to_access >= virtual_bucket_n) {
            CUDA_GROUP_DEBUG_PRINTF("***************step 2 all locks got", 0);
            extState.step = 3;
        }
    }

    // if (extState.step == 3) {
    //     // debug
    //     CUDA_GROUP_DEBUG_PRINTF("***************step 3 failed", 0);
    //     shouldReleaseAllThisBucketLock = true;
    //     shouldReleaseCellLock = true;
    //     insert_res = EXT_MOVE_RES_FAILD;
    // }

    // accessing workspace lock
    if (extState.step == 3) {
        size_t start_id = (group_id) % total_workspaces_number;
        bool workspace_lock_get = false;
        for (int i = 0; i < WORKSPACE_LOCK_TRY_LIMIT; i++) {
            size_t this_workspace_id = (start_id + i) % total_workspaces_number;
            T* lock_address = WORKSPACE_LOCK(sharedInsert, this_workspace_id);
            workspace_lock_get = workspaceLockFreeRequest(groupLane, group_mask, insert_group_size, lock_address);
            if (workspace_lock_get) {
                extState.this_workspace_id = this_workspace_id;
                CUDA_GROUP_DEBUG_PRINTF("***************step 3 get workspace %lu, start_id %lu, total_workspaces_number %d", this_workspace_id, start_id, total_workspaces_number);
                break;
            } else {
                CUDA_GROUP_DEBUG_PRINTF("***************step 3 failed to get workspace %u, try next...", this_workspace_id);
            }
        }
        if (workspace_lock_get) {
            // initworkspace
            for (int vbid = 0; vbid < virtual_bucket_n; vbid++) {
                int cellId = HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
                int thisBucketId = HASH_BUCKET_ID(cellId, vbid, virtual_bucket_n, USED_CELLS_ARRAY_LENGTH(cell_length), cvbid, bucket_n, rand_seed);
                setupWorkspaceKthBucket<T, bucket_cap, insert_group_size, virtual_bucket_n>(
                    extState.this_workspace_id,
                    cellId, thisBucketId, vbid,
                    data, cell_length, rand_seed,
                    groupLane, group_mask);
            }

            // for offset x->y: getTransferPairs(); checkValidaty();
            CELL_T new_offset;
            int serialDelta;
            bool have_valid_new_offset = false;
            for (new_offset = 0; new_offset < virtual_bucket_n; new_offset++) {
                int newBucketSerial = HASH_BUCKET_S(key, rand_seed, new_offset, virtual_bucket_n);
                serialDelta = (newBucketSerial - bucketSerial + virtual_bucket_n) % virtual_bucket_n;
                // assert((HASH_BUCKET_S(key, rand_seed, new_offset, virtual_bucket_n)+1) %virtual_bucket_n ==  (HASH_BUCKET_S(key, rand_seed, offset, virtual_bucket_n)+1+serialDelta)%virtual_bucket_n);
                bool valid = true;
                int turn = 0;
                while (valid) {
                    int fromvbid = turn * insert_group_size + groupLane;
                    int tovbid = (fromvbid + serialDelta) % virtual_bucket_n;
                
                    if (fromvbid >= virtual_bucket_n) {
                        break; 
                    }
                    
                    int fthis = (int)(*WORKSPACE_THISCELL_I(sharedInsert, extState.this_workspace_id, fromvbid));
                    int tempty = (int)(*WORKSPACE_EMPTY_I(sharedInsert, extState.this_workspace_id, tovbid));
                    int tthis = (int)(*WORKSPACE_THISCELL_I(sharedInsert, extState.this_workspace_id, tovbid));
                    if (bucketSerial == fromvbid) {
                        fthis = fthis + 1;
                    }
                    if (bucketSerial == tovbid) {
                        tempty = tempty - 1;
                        tthis = tthis + 1;
                    }

                    valid = checkBucketTransferValid(
                        fthis,tempty, tthis
                    );

                    #ifdef EXT_MOVE_DEBUG
                    if (valid && (bucketSerial == fromvbid || bucketSerial == tovbid)) {
                        printf("valid move method kv %llu fromvb %d tovb %d: fthis %d, tempty %d, tthis %d\n", kv, fromvbid, tovbid, fthis, tempty, tthis);
                    }
                    #endif

                    // if (valid) {
                    //     assert(tempty >= 0);
                    // }
                 
                    ++turn; 
                }
                __syncwarp(group_mask);
                int new_is_valid = __all_sync(group_mask, valid);
                if (new_is_valid != 0) {
                    have_valid_new_offset = true;
                    break;
                }
            }

            // {//debug
            //     CUDA_GROUP_DEBUG_PRINTF("***************step 3 failed", 0);
            //     shouldReleaseAllThisBucketLock = true;
            //     shouldReleaseCellLock = true;
            //     insert_res = EXT_MOVE_RES_FAILD;
            // }

            // if (false) {
            if (have_valid_new_offset) {
                if (serialDelta > 0) {
                    int circle_num = gcd(virtual_bucket_n, serialDelta);
                    int circle_len = virtual_bucket_n / circle_num;
                    assert(circle_len >= 1 && (virtual_bucket_n == circle_num * circle_len));
                    {    
                        for (int startfromvbid = 0; startfromvbid < circle_num; startfromvbid++) {
                            int fromvbid, tovbid;
                            int bufferedvbid; // debug
                            for (int j = 0; j < circle_len; j++) {
                                if (j == 0) {
                                    fromvbid = startfromvbid;
                                    tovbid = (fromvbid + serialDelta) % virtual_bucket_n;
                                    
                                    assert(fromvbid != tovbid);
                                    transferCircularMoveBucketInWorkspace<T, bucket_cap, insert_group_size, virtual_bucket_n>(
                                        fromvbid, false,
                                        tovbid, 
                                        extState.this_workspace_id,
                                        cellId, 
                                        kv, (bucketSerial == fromvbid),
                                        cell_length, rand_seed,
                                        groupLane, group_mask);
                                    bufferedvbid = tovbid;

                                    #ifdef EXT_MOVE_DEBUG
                                    printf("[%d] key %u v%d -> v%d\n",threadIdx.x, key, fromvbid, tovbid);
                                    #endif

                                    fromvbid = tovbid;
                                    tovbid = (fromvbid + serialDelta) % virtual_bucket_n;
                                } else {
                                    assert(fromvbid != tovbid);
                                    assert(fromvbid == bufferedvbid);
                                    transferCircularMoveBucketInWorkspace<T, bucket_cap, insert_group_size, virtual_bucket_n>(
                                        fromvbid, true,
                                        tovbid, 
                                        extState.this_workspace_id,
                                        cellId, 
                                        kv, (bucketSerial == fromvbid),
                                        cell_length, rand_seed,
                                        groupLane, group_mask);
                                    bufferedvbid = tovbid;

                                    #ifdef EXT_MOVE_DEBUG
                                    printf("[%d] key %u v%d -> v%d\n",threadIdx.x, key, fromvbid, tovbid);
                                    #endif

                                    fromvbid = tovbid;
                                    tovbid = (fromvbid + serialDelta) % virtual_bucket_n;
                                }
                            }
                        }
                    }
                    
                    #ifdef EXT_MOVE_DEBUG
                    printf("=================Ext Move serialDelta != 0 insert sucesssful, key %u\n", key);
                    #endif

                } else if (serialDelta == 0) {

                    #ifdef EXT_MOVE_DEBUG
                    if (groupLane == 0) {
                        printf("serialDelta == 0\n");
                    }
                    #endif

                    DirectlyInsertBucketInWorkspace<T, bucket_cap, insert_group_size, virtual_bucket_n>(bucketSerial, extState.this_workspace_id, cellId, kv, cell_length, rand_seed, groupLane, group_mask);
                    
                    #ifdef EXT_MOVE_DEBUG
                    printf("=================Ext Move serialDelta === 0 insert sucesssful, key %u\n", key);
                    #endif
                }
                        
                for (int vbid = 0; vbid < virtual_bucket_n; vbid++) {
                    int bucketId = HASH_BUCKET_ID(cellId, vbid, virtual_bucket_n, USED_CELLS_ARRAY_LENGTH(cell_length), cvbid, bucket_n, rand_seed);
                    writeWorkspaceKthBucketBackToGlobalBucket<T, bucket_cap, insert_group_size, virtual_bucket_n>(
                        extState.this_workspace_id, vbid,
                        (T*)(BUCKET_I(data, bucketId, bucket_cap)),
                        groupLane, group_mask);
                }

                CELL_AT_I(cells, cellId) = GET_CELL_K_FROM_OFFSET_CVBID(new_offset, cvbid, virtual_bucket_n);

                shouldReleaseAllThisBucketLock = true;
                shouldReleaseCellLock = true;

                CUDA_GROUP_DEBUG_PRINTF("***************step 3 find valid offset", 0);
                insert_res = EXT_MOVE_RES_SUC;
            } else {
                // TODO temporarily discard here,  
                // // IncreaseCVBIDWithoutConflict()
                // extState.step = 4;
                
                shouldReleaseCellLock = true;
                shouldReleaseAllThisBucketLock = true;
                insert_res = EXT_MOVE_RES_FAILD;
                CUDA_GROUP_DEBUG_PRINTF("***************step 3 cannot find valid offset, abort", 0);
            }
        } 
        else {
            CUDA_GROUP_DEBUG_PRINTF("***************step 3 failed EXT_MOVE_RES_PENDING_SHORT", 0);
            insert_res = EXT_MOVE_RES_PENDING_SHORT;
            {//debug
                shouldReleaseAllThisBucketLock = true;
                shouldReleaseCellLock = true;
                extState.step = 1;
            }
        }
    }

    if (shouldReleaseAllThisBucketLock) {
        int turn = 0;
        T* workspace_lock = WORKSPACE_LOCK(sharedInsert, extState.this_workspace_id);
        workspaceLockRelease(groupLane, workspace_lock);
        while (turn * insert_group_size + groupLane < virtual_bucket_n) {
            int hadBucketId = HASH_BUCKET_ID(cellId, turn * insert_group_size + groupLane, virtual_bucket_n, USED_CELLS_ARRAY_LENGTH(cell_length), cvbid, bucket_n, rand_seed);
            CUDA_GROUP_DEBUG_PRINTF("***************release this lock %d", hadBucketId);
            lockRelease(groupLane, bucket_locks + hadBucketId, groupLane);
            ++turn;
        } 
        // for (int rvbid = 0; rvbid < virtual_bucket_n; rvbid++) {
        //     int rbucketId = HASH_BUCKET_ID(cellId, rvbid, virtual_bucket_n, USED_CELLS_ARRAY_LENGTH(cell_length), cvbid, bucket_n, rand_seed);
        //     CUDA_GROUP_DEBUG_PRINTF("***************release this lock %d", rbucketId);
        //     lockRelease(groupLane, bucket_locks + rbucketId);
        // }
        __syncwarp(group_mask);
    }

 
    if (shouldReleaseCellLock) {
        CUDA_GROUP_DEBUG_PRINTF("***************release cell lock %d", cellId);
        lockRelease(groupLane, cell_locks + cellId);
        __syncwarp(group_mask);
    }

    return insert_res;
}


/***
* steps:
* 1. make mask for frombucket and tobucket
* 2. hold value of tobucket in register
* 3. transfer frombucket to tobucket 
* 4. write hold value of tobucket to bufferbucket
* Note: if kvIsInTransfer is true, write kv to toBucket.
*/
template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ void transferCircularMoveBucketInWorkspace(
    int fromBucket_i, bool fromIsBuffer,
    int toBucket_i,
    size_t workspace_id,
    int thisCellId,
    T kv, bool kvIsInTransfer,
    const int cell_length, const int rand_seed,
    const int groupLane, const int group_mask)
{
    // remember kv need special treatment   
    constexpr int accessTurn = bucket_cap / insert_group_size;
    extern __shared__ T sharedInsert[];

    T* fromBucket;
    if (fromIsBuffer) {
        fromBucket = WORKSPACE_BUFFER_BUCKET(sharedInsert, workspace_id);
    } else {
        fromBucket = WORKSPACE_BUCKET_I(sharedInsert, workspace_id, fromBucket_i);
    }
    T* toBucket = WORKSPACE_BUCKET_I(sharedInsert, workspace_id, toBucket_i);
    T* bufferBucket = WORKSPACE_BUFFER_BUCKET(sharedInsert, workspace_id);
    assert(fromBucket != toBucket);
    assert(bucket_cap <= 32);

    T slots[accessTurn];

    #pragma unroll
    for (int t = 0; t < accessTurn; t++) {
        slots[t] = (*BUCKET_J_TH_SLOT(fromBucket, SLOT(groupLane, insert_group_size, t, accessTurn)));
    }
    
    unsigned int fb_thiscell_local_mask = 0;
    for (int t = 0; t < accessTurn; t++) {
        if (!checkAllBitsSet(slots[t]) && isBelongsToThisCell(slots[t], thisCellId, cell_length, rand_seed)) {
            fb_thiscell_local_mask |= (((unsigned int)1)<<(SLOT(groupLane, insert_group_size, t, accessTurn)));
        }
    }
    __syncwarp(group_mask);
    unsigned int fb_thiscell_mask = dirty_reduce_or_sync(group_mask, insert_group_size, groupLane, fb_thiscell_local_mask);
    
    if (fb_thiscell_local_mask != 0) {
        assert((fb_thiscell_local_mask & fb_thiscell_mask) == fb_thiscell_local_mask);
    }

    #pragma unroll
    for (int t = 0; t < accessTurn; t++) {
        slots[t] = (*BUCKET_J_TH_SLOT(toBucket, SLOT(groupLane, insert_group_size, t, accessTurn)));
    }

    unsigned int tb_et_local_mask = 0;
    for (int t = 0; t < accessTurn; t++) {
        if (checkAllBitsSet(slots[t])) {
            tb_et_local_mask |= (((unsigned int)1)<<(SLOT(groupLane, insert_group_size, t, accessTurn)));
        }
        else if (isBelongsToThisCell(slots[t], thisCellId, cell_length, rand_seed)) {
            tb_et_local_mask |= (((unsigned int)1)<<(SLOT(groupLane, insert_group_size, t, accessTurn)));
        }
    }
    __syncwarp(group_mask);
    unsigned int tb_et_mask = dirty_reduce_or_sync(group_mask, insert_group_size, groupLane, tb_et_local_mask);
    
    unsigned int tb_final_empty_mask = 0;
    
    
    
    {    
        if (__popc(fb_thiscell_mask) > __popc(tb_et_mask)) {
            T fthis = (*WORKSPACE_THISCELL_I(sharedInsert, workspace_id, fromBucket_i));
            T tempty = (*WORKSPACE_EMPTY_I(sharedInsert, workspace_id, toBucket_i));
            T tthis = (*WORKSPACE_THISCELL_I(sharedInsert, workspace_id, toBucket_i));
            printf("ERROR: popc_ft %d > popc_tet %d, ft = %llu te = %llu tt = %llu, fb_thiscell=%u, tb_et_mask=%u, from %d(buf %d) to %d, iskv %d, kv %llu\n", __popc(fb_thiscell_mask), __popc(tb_et_mask), fthis, tempty, tthis, fb_thiscell_mask, tb_et_mask, fromBucket_i, fromIsBuffer, toBucket_i, kvIsInTransfer, kv);
            assert(false);
        }
    }

    for (int t = 0; t < accessTurn; t++) {
        unsigned tbSlotId = (unsigned)SLOT(groupLane, insert_group_size, t, accessTurn);
        int r = isRthOneBit(tb_et_mask, tbSlotId);
        if (r != -1) {
            unsigned fbSlotId = getRthOneBitPos(fb_thiscell_mask, r);
            T writeValue;
            if ((fbSlotId == 0xffffffff)) {
                writeValue = getAllBitsSet<T>();
                tb_final_empty_mask |= (((unsigned int)1) << tbSlotId);
            } else {
                writeValue = (*BUCKET_J_TH_SLOT(fromBucket, fbSlotId));
            }
            (*BUCKET_J_TH_SLOT(toBucket, tbSlotId)) = writeValue;
        }
        __syncwarp(group_mask);
    }
    if (kvIsInTransfer) {
        unsigned final_empty = dirty_reduce_or_sync(group_mask, insert_group_size, groupLane, tb_final_empty_mask);
        if (groupLane == 0) {
            unsigned pos = getRthOneBitPos(final_empty, 0);
            if (pos == 0xffffffff) {
                T fthis = (*WORKSPACE_THISCELL_I(sharedInsert, workspace_id, fromBucket_i));
                T tempty = (*WORKSPACE_EMPTY_I(sharedInsert, workspace_id, toBucket_i));
                T tthis = (*WORKSPACE_THISCELL_I(sharedInsert, workspace_id, toBucket_i));
                printf("ERROR pos = 0xffffffff in final_empty %u: popc_ft %d > popc_tet %d, ft = %llu te = %llu tt = %llu, fb_thiscell=%u, tb_et_mask=%u, from %d(buf %d) to %d, iskv %d, kv %llu\n", final_empty, __popc(fb_thiscell_mask), __popc(tb_et_mask), fthis, tempty, tthis, fb_thiscell_mask, tb_et_mask, fromBucket_i, fromIsBuffer, toBucket_i, kvIsInTransfer, kv);
                assert(pos!=0xffffffff);
            }
            (*BUCKET_J_TH_SLOT(toBucket, pos)) = kv;
        }
    }
    __threadfence_block();

    __syncwarp(group_mask);
    #pragma unroll
    for (int t = 0; t < accessTurn; t++) {
        (*BUCKET_J_TH_SLOT(bufferBucket, SLOT(groupLane, insert_group_size, t, accessTurn))) = slots[t];
    }
    
    __syncwarp(group_mask);
    __threadfence_block();
}


template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ void DirectlyInsertBucketInWorkspace(
    int toBucket_i,
    size_t workspace_id,
    int thisCellId,
    T kv, 
    const int cell_length, const int rand_seed,
    const int groupLane, const int group_mask)
{
    // remember kv need special treatment   
    constexpr int accessTurn = bucket_cap / insert_group_size;
    extern __shared__ T sharedInsert[];

    T* toBucket = WORKSPACE_BUCKET_I(sharedInsert, workspace_id, toBucket_i);
    assert(bucket_cap <= 32);

    bool written = false;
    for (int t = 0; t < accessTurn; t++) {
        T slot = (*BUCKET_J_TH_SLOT(toBucket, SLOT(groupLane, insert_group_size, t, accessTurn)));
        int emptyLaneId = ballotLowestWarpLaneIdWithTrue(checkAllBitsSet(slot), group_mask) % insert_group_size;
        if (emptyLaneId >= 0) {
            if (groupLane == emptyLaneId) {
                (*BUCKET_J_TH_SLOT(toBucket, SLOT(groupLane, insert_group_size, t, accessTurn))) = kv;
            }
            written = true;
            break;
        }
    }
    assert(written);
    __syncwarp(group_mask);
    __threadfence_block();
}

/***
*   
*/
template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ void setupWorkspaceKthBucket(
    size_t workspace_id,
    int cellId, int bucketId, int vbid,
    T *const data, const int cell_length, const int rand_seed,
    const int groupLane, const int group_mask)
{
    using HT = typename HalfTypeT<T>::HT;
    extern __shared__ T sharedInsert[];
    constexpr int accessTurn = bucket_cap / insert_group_size;

    T copykvs[accessTurn];

    #pragma unroll
    for (int t = 0; t < accessTurn; t++) {
        copykvs[t] = BUCKET_I_ELEMENT_J(
            data, bucketId,
            SLOT(groupLane, insert_group_size, t, accessTurn),
            bucket_cap);
    }
    __threadfence_block();
    __syncwarp(group_mask);
    
    unsigned isEmptyCount = 0;
    unsigned isThisCellCount = 0;
    for (int t = 0; t < accessTurn; t++) {
        bool isEmpty = false;
        bool isThisCell = false;
        *(WORKSPACE_BUCKET_I_J(sharedInsert, workspace_id, vbid, SLOT(groupLane, insert_group_size, t, accessTurn))) = copykvs[t];
        if (checkAllBitsSet(copykvs[t])) {
            isEmpty = true;
        }
        else {
            isThisCell = (isBelongsToThisCell(copykvs[t], cellId, cell_length, rand_seed));
        }
        __syncwarp(group_mask);
        isEmptyCount += __popc(__ballot_sync(group_mask, isEmpty));
        isThisCellCount += __popc(__ballot_sync(group_mask, isThisCell));
    }

    if (groupLane == 0) {
        (*WORKSPACE_EMPTY_I(sharedInsert, workspace_id, vbid)) = (T)isEmptyCount;
        (*WORKSPACE_THISCELL_I(sharedInsert, workspace_id, vbid)) = (T)isThisCellCount;
    }
    __threadfence_block();
    __syncwarp(group_mask);
}


template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ void writeWorkspaceKthBucketBackToGlobalBucket(
    size_t workspace_id, int vbid,
    T* globalBucket,
    const int groupLane, const int group_mask)
{
    extern __shared__ T sharedInsert[];
    constexpr int accessTurn = bucket_cap / insert_group_size;

    T* workspaceBucket = WORKSPACE_BUCKET_I(sharedInsert, workspace_id, vbid);
    #pragma unroll
    for (int t = 0; t < accessTurn; t++) {
        (*BUCKET_J_TH_SLOT(globalBucket, SLOT(groupLane, insert_group_size, t, accessTurn))) = (*BUCKET_J_TH_SLOT(workspaceBucket, SLOT(groupLane, insert_group_size, t, accessTurn)));
    }
    __syncwarp(group_mask);
    __threadfence();
}




/**
* Direct insert success: return 0
* Direct insert bucket full: return 1
* Lock access failed: return 2
*/ 
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
)
{
  using HT = typename HalfTypeT<T>::HT;
  int insert_res;
  HT key, value;
  splitKV(kv, key, value);

  int cellId = HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));

  bool cell_lock_get = lockFreeRequest(groupLane, group_mask, insert_group_size, cell_locks + cellId);
  if (cell_lock_get) {
    CELL_T cell_value;
    if (groupLane == 0)
    {
        cell_value = CELL_AT_I(cells, cellId);
    }
    cell_value = __shfl_sync(group_mask, cell_value, 0, insert_group_size);
    CELL_T offset = GET_OFFSET_FROM_CELL(cell_value, virtual_bucket_n);
    CELL_T cvbid = GET_CVBID_FROM_CELL(cell_value, virtual_bucket_n);

    int bucketSerial = HASH_BUCKET_S(key, rand_seed, offset, virtual_bucket_n);
    int bucketId = HASH_BUCKET_ID(cellId, bucketSerial, virtual_bucket_n, USED_CELLS_ARRAY_LENGTH(cell_length), cvbid, bucket_n, rand_seed);
    
    bool bucket_lock_get = (bucketLockRequest(groupLane, group_mask, (LOCK_T)1, insert_group_size, bucket_locks + bucketId) == 0);

    if (bucket_lock_get) {
        __syncwarp(group_mask);
        constexpr int accessTurn = bucket_cap / insert_group_size;
        int target;
        int warpLaneEmptySlot = scanBucketForEmptySlot<T, bucket_cap, insert_group_size,virtual_bucket_n>
                                                        (data, bucketId, groupLane, group_mask, target);
        if (warpLaneEmptySlot >= 0) {
            if (groupLane == (warpLaneEmptySlot % insert_group_size))
            {
                BUCKET_I_ELEMENT_J(
                    data, bucketId,
                    SLOT(groupLane, insert_group_size, target, accessTurn),
                    bucket_cap) = kv;
            }
            insert_res = DIRECT_INSERT_RES_SUC;
        }
        else {
            insert_res = DIRECT_INSERT_RES_BKT_FULL;
        }
        __syncwarp(group_mask);
        lockRelease(groupLane, bucket_locks + bucketId);
    } else {  
        CUDA_GROUP_DEBUG_PRINTF("REQUEST BUCKET %d LOCK FAILED", bucketId);
        insert_res = DIRECT_INSERT_RES_LOCK_FAILD;
    }
    lockRelease(groupLane, cell_locks + cellId);
  } else {
    CUDA_GROUP_DEBUG_PRINTF("REQUEST CELL %d LOCK FAILED", cellId);
    insert_res = DIRECT_INSERT_RES_LOCK_FAILD;
  }
  
  return insert_res;
}


