#pragma once

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__global__ void DIOnlyInsertKeyValueKernel(
    T *const
        kv_array, // type T is compacted, its first half is Key, second half is Value
    const int n, // kv_array length is n
    LOCK_T *const bucket_locks, T *const data, const int bucket_n,
    CELL_T *const cells, const int cell_length, const int rand_seed,
    bool *const insert_result) {

  // Check to make sure insert_group_size is valid
  assert(insert_group_size <= bucket_cap);

  const size_t idGlobal = threadIdx.x + blockIdx.x * blockDim.x;
  const size_t threadN = gridDim.x * blockDim.x;
  const size_t groupLane = idGlobal % insert_group_size;
  const unsigned group_mask = getWarpMask(insert_group_size, threadIdx.x);
  int insert_result_write_back_position = -1;

  size_t nxtPos = idGlobal;
  T own_kv;
  bool isComplete = false;

  GROUP_ROUND_CNT_TYPE current_group_round = 0;
  while (true) {
    ++current_group_round;

    // Ensure `nxtPos` does not exceed the number of elements
    if (!isComplete) {
      if (nxtPos < n) {
        own_kv = kv_array[nxtPos];
        insert_result_write_back_position = (int)nxtPos;
        nxtPos += threadN;
      } else {
        isComplete = true;
      }
    }

    bool completeOwnTurn = false;

    // Each group round contains $insert_group_size$ turns.
    for (int turn = 0; turn < insert_group_size; turn++) {
      bool canBeLeader = (!completeOwnTurn && !isComplete);
      int leaderWarpLane =
          ballotLowestWarpLaneIdWithTrue(canBeLeader, group_mask);

      if (leaderWarpLane >= 0) {
        int leaderGroupLane = leaderWarpLane % insert_group_size;
        bool isLeader = (leaderGroupLane == groupLane);
        if (isLeader)
          completeOwnTurn = true;

        T kv =
            __shfl_sync(group_mask, own_kv, leaderGroupLane, insert_group_size);

        int direct_insert_res =
            DIOnlyPutKeyValueIntoBucket<T, bucket_cap, insert_group_size,
                                        virtual_bucket_n>(
                kv, data, bucket_n, cells, cell_length, rand_seed, threadN,
                groupLane, group_mask);
        // Ensure insert result position is within bounds
        if (insert_result_write_back_position >= 0 &&
            insert_result_write_back_position < n) {
          if (isLeader) {
            if (direct_insert_res == DIRECT_INSERT_RES_BKT_FULL) {
              insert_result[insert_result_write_back_position] = false;
            }
          }
        } else {
          printf("ERROR: insert_result_write_back_position out of bounds: %d\n",
                 insert_result_write_back_position);
        }
      } else {
        break;
      }
      __syncwarp(group_mask);
    }

    if (__all_sync(group_mask, isComplete == true))
      break;

    // Avoid infinite loop in case of error
    if (current_group_round > (GROUP_ROUND_CNT_TYPE)n * 1000) {
      printf("ERROR: TOO MANY ROUNDS, threadGlobalID %d, nxtPos %d, isComplete "
             "%d\n",
             idGlobal, nxtPos, isComplete);
      break;
    }
  }
}

template <typename T, int bucket_cap, int insert_group_size,
          int virtual_bucket_n>
__device__ int
DIOnlyPutKeyValueIntoBucket(T kv, T *const data, const int bucket_n,
                            CELL_T *const cells, const int cell_length,
                            const int rand_seed, const int threadN,
                            const int groupLane, const int group_mask) {

  using HT = typename HalfTypeT<T>::HT;
  HT key, value;
  splitKV(kv, key, value);

  int insert_res = -1;

  int cellId =
      HASH_CELL_ID(key, rand_seed, USED_CELLS_ARRAY_LENGTH(cell_length));
  CELL_T cell_value;

  // Ensure that thread 0 in the warp is reading cell_value
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

  __syncwarp(group_mask);

  constexpr int accessTurn = bucket_cap / insert_group_size;
  T slots[accessTurn];
  // printf("Coming here\n");
  T EMPTY_SLOT_CONST = getAllBitsSet<T>();
  // printf("Coming here 2.0\n");

  // Ensure that we don't access out-of-bounds memory in slots array
  // printf("value of accessturn: %d\n", accessTurn);
  for (int t = 0; t < accessTurn; t++) {
    uint32_t i = SLOT(groupLane, insert_group_size, t, accessTurn);
    // printf("Value of i: %u\n", i);
    // printf("Value of t: %d\n", t);
    // printf("Array index for data: %u\n",);
    uint64_t index = (bucketId * bucket_cap + i);
    // if (index > (bucket_n * bucket_cap))
    //   printf("Out of bounds\n");
    slots[t] = data[index];
    // if (slots[t] == ~uint64_t(0)){
    //   printf("Error is there\n");
    // }
  }
  int t = 0;
  while (t < accessTurn) {
    bool emptySlotFound = false;
    if (checkAllBitsSet(slots[t])) {
      emptySlotFound = true;
    }
    while (true) {
      int warpLaneEmptySlot =
          ballotLowestWarpLaneIdWithTrue(emptySlotFound, group_mask);
      if (warpLaneEmptySlot >= 0) {
        if (groupLane == (warpLaneEmptySlot % insert_group_size)) {
          T *bucketAddress = &BUCKET_I_ELEMENT_J(
              data, bucketId, SLOT(groupLane, insert_group_size, t, accessTurn),
              bucket_cap);

          // Ensure atomicCAS is used correctly with valid memory addresses
          T old = atomicCAS((unsigned long long int *)bucketAddress,
                            (unsigned long long int)EMPTY_SLOT_CONST,
                            (unsigned long long int)kv);

          if (old == EMPTY_SLOT_CONST) {
            insert_res = DIRECT_INSERT_RES_SUC;
          } else {
            emptySlotFound = false;
          }
        }
      } else {
        break;
      }

      int successLane = ballotLowestWarpLaneIdWithTrue(
          insert_res == DIRECT_INSERT_RES_SUC, group_mask);
      if (successLane >= 0) {
        insert_res = DIRECT_INSERT_RES_SUC;
        break;
      }
    }

    if (insert_res == DIRECT_INSERT_RES_SUC)
      break;
    t += 1;
  }

  if (insert_res == -1) {
    insert_res = DIRECT_INSERT_RES_BKT_FULL;
  }

  __syncwarp(group_mask);
  return insert_res;
}
