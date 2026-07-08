// global constant and macro that is mostly static
#pragma once
#include <type_traits>

#define remove_ref_cst_pure_decltype(x) std::remove_const_t<std::remove_reference_t<decltype(x)>>

#define CELL_AT_I(_cells, i) (_cells[i])
#define ACTUAL_CELLS_ARRAY_LENGTH(_cells_length) (_cells_length)
#define USED_CELLS_ARRAY_LENGTH(_cells_length) (_cells_length)
#define ACTIVE_MASK 0xffffffff
#define BUCKET_I_ELEMENT_J(_data, i, j, bucket_cap) \
    ((_data)[(i) * (bucket_cap) + (j)])
#define BUCKET_I(_data, i, bucket_cap) \
    (&((_data)[(i) * (bucket_cap)]))
#define HASH_CELL_ID(key, rand_seed, used_cell_length) \
    (_HASH_T<remove_ref_cst_pure_decltype(key)>(key, rand_seed) % (used_cell_length))
#define HASH_BUCKET_S(key, rand_seed, offset, vitual_bucket_n) \
    ((_HASH_T<remove_ref_cst_pure_decltype(key)>(key, (rand_seed) ^ 123456789) + (offset)) % vitual_bucket_n)

// #ifdef VIRTUAL_TO_BUCKET_RANGE_STRATEGY
// #define HASH_BUCKET_ID(cell_id, bucket_serial, virtual_bucket_n, cell_length, \
//                        bucket_n, rand_seed)                                   \
//     ((int)((cell_id) * 1.0 * (((bucket_n) + (virtual_bucket_n)) / ((cell_length) * 1.0)) + (bucket_serial)) % (bucket_n))
// #else
#define HASH_BUCKET_ID(cell_id, bucket_serial, virtual_bucket_n, cell_length, cvbid, \
                       bucket_n, rand_seed)                                   \
    (_HASH_int(((cell_id) << 10) | (bucket_serial), (rand_seed) ^ 789101112 * (cvbid)) % (bucket_n))
// #endif

#define GET_OFFSET_FROM_CELL(cell_value, V) ((cell_value) % (V))
#define GET_CVBID_FROM_CELL(cell_value, V) ((cell_value) / (V))
#define GET_CELL_K_FROM_OFFSET_CVBID(offset, cvbid, V) ((cvbid) * (V) + (offset))

#define SPLIT_LEVEL_SEED(base_seed, level) ((base_seed) * (level + 1))

// L2_AS_FAST_MEMORY related
#define PTR_TO_INDEX_IN_L2(_cells) \
    (_cells + SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE / sizeof(CELL_T))
#ifdef L2_AS_FAST_MEMORY
#define CELL_AT_I_GPU(_cells_shared, _cells_l2, i) \
    cell_at_i_gpu(_cells_shared, _cells_l2, i)
#else
#define CELL_AT_I_GPU(_cells_shared, _cells_l2, i) CELL_AT_I(_cells_shared, i)
#endif

// CSI and OSPS related
// #define CELL_LOCAL_ID(cell_global_id, SM_ID, cell_sm_length) \
//     ((cell_global_id) - (SM_ID) * (cell_sm_length))
#define CELL_LOCAL_ID(cell_global_id, SM_ID, cell_sm_length) \
     ((cell_global_id) % (cell_sm_length))
#define KEY_TO_SM_ID(key, rand_seed, cell_length, sm_cell_block_length) \
    ((HASH_CELL_ID(key, rand_seed, (cell_length))) / sm_cell_block_length)

#define DEVICE_PRINTF(format, ...)                                             \
    do                                                                         \
    {                                                                          \
        printf("===========device [%d, %d]: " format, blockIdx.x, threadIdx.x, \
               __VA_ARGS__);                                                   \
    } while (0)

#define SLOT(groupLane, group_size, turn, totalTurn) \
    ((groupLane) * (totalTurn) + (turn))

template <typename T, int Length>
struct CUDAVectorType;

template <typename T>
struct CUDAVectorType<T, 1>
{
    static_assert(std::is_same<T, int16_t>::value || std::is_same<T, uint16_t>::value || std::is_same<T, int32_t>::value || std::is_same<T, uint32_t>::value || std::is_same<T, int64_t>::value || std::is_same<T, uint64_t>::value,
                  "Unsupported type T");
    using type = typename std::conditional<
        std::is_same<T, int16_t>::value, short1,
        typename std::conditional<
            std::is_same<T, uint16_t>::value, ushort1,
            typename std::conditional<
                std::is_same<T, int32_t>::value, int1,
                typename std::conditional<
                    std::is_same<T, uint32_t>::value, uint1,
                    typename std::conditional<
                        std::is_same<T, int64_t>::value, longlong1,
                        typename std::conditional<
                            std::is_same<T, uint64_t>::value, ulonglong1,
                            void>::type>::type>::type>::type>::type>::type;
};

template <typename T>
struct CUDAVectorType<T, 2>
{
    static_assert(std::is_same<T, int16_t>::value || std::is_same<T, uint16_t>::value || std::is_same<T, int32_t>::value || std::is_same<T, uint32_t>::value || std::is_same<T, int64_t>::value || std::is_same<T, uint64_t>::value,
                  "Unsupported type T");
    using type = typename std::conditional<
        std::is_same<T, int16_t>::value, short2,
        typename std::conditional<
            std::is_same<T, uint16_t>::value, ushort2,
            typename std::conditional<
                std::is_same<T, int32_t>::value, int2,
                typename std::conditional<
                    std::is_same<T, uint32_t>::value, uint2,
                    typename std::conditional<
                        std::is_same<T, int64_t>::value, longlong2,
                        typename std::conditional<
                            std::is_same<T, uint64_t>::value, ulonglong2,
                            void>::type>::type>::type>::type>::type>::type;
};

template <typename T>
struct CUDAVectorType<T, 4>
{
    static_assert(std::is_same<T, int16_t>::value || std::is_same<T, uint16_t>::value || std::is_same<T, int32_t>::value || std::is_same<T, uint32_t>::value,
                  "Unsupported type T");
    using type = typename std::conditional<
        std::is_same<T, int16_t>::value, short4,
        typename std::conditional<
            std::is_same<T, uint16_t>::value, ushort4,
            typename std::conditional<
                std::is_same<T, int32_t>::value, int4,
                typename std::conditional<std::is_same<T, uint32_t>::value,
                                          uint4, void>::type>::type>::type>::
        type;
};

template <typename T, int Length>
using CUDAVectorType_t = typename CUDAVectorType<T, Length>::type;

template <typename T, int Length>
struct AssignImpl;

template <typename T>
struct AssignImpl<T, 1>
{
    __device__ void
    operator()(T *arr, const CUDAVectorType_t<T, 1> &t)
    {
        arr[0] = t.x;
    }
};

template <typename T>
struct AssignImpl<T, 2>
{
    __device__ void
    operator()(T *arr, const CUDAVectorType_t<T, 2> &t)
    {
        arr[0] = t.x;
        arr[1] = t.y;
    }
};

template <typename T>
struct AssignImpl<T, 4>
{
    __device__ void
    operator()(T *arr, const CUDAVectorType_t<T, 4> &t)
    {
        arr[0] = t.x;
        arr[1] = t.y;
        arr[2] = t.z;
        arr[3] = t.w;
    }
};

template <typename T, int Length>
__device__ void
splitVector(T *arr, const CUDAVectorType_t<T, Length> &t)
{
    AssignImpl<T, Length> assignImpl;
    assignImpl(arr, t);
}








// unverified
