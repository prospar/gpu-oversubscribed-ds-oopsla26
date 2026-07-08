// Utility functions that has no dependencies with this project
#pragma once

#include <assert.h>
#include <typeinfo>

#define ALL_BITS_SET_8BIT (uint8_t)0xFF
#define ALL_BITS_SET_16BIT (uint16_t)0xFFFF
#define ALL_BITS_SET_32BIT (uint32_t)0xFFFFFFFF
#define ALL_BITS_SET_64BIT (uint64_t)0xFFFFFFFFFFFFFFFF



// cqueue related
#define CQ_IS_FULL(cq, front, rear, size) \
    (((front) == ((rear) + 1)) || ((front) == 0 && (rear) == ((size)-1)))
#define CQ_IS_EMPTY(cq, front, rear, size) ((front) == (rear))
#define CQ_PUSH(cq, front, rear, size, elem) \
    {                                        \
        rear = ((rear) + 1) % (size);        \
        cq[rear] = (elem);                   \
    }
#define CQ_HEAD(cq, front, rear, size) (cq[front])
#define CQ_POP(cq, front, rear, size)   \
    {                                   \
        front = ((front) + 1) % (size); \
    }

// basic functions ver.1

#define gpuErrchk(ans)                        \
    {                                         \
        gpuAssert((ans), __FILE__, __LINE__); \
    }

inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort = true)
{
    if (code != cudaSuccess)
    {
        fprintf(stderr, "GPUassert: %s %s %d\n", cudaGetErrorString(code),
                file, line);
        if (abort)
            exit(code);
    }
}

template <typename T>
inline __host__ __device__ bool
checkAllBitsSet(T val)
{
    // TODO
    return (val == ~uint64_t(0));
    // Determine the size of the type at compile-time
    // constexpr int typeSize = sizeof(T);
    // switch (typeSize)
    // {
    //     case 1:
    //         return (val & ALL_BITS_SET_8BIT) == ALL_BITS_SET_8BIT;
    //     case 2:
    //         return (val & ALL_BITS_SET_16BIT) == ALL_BITS_SET_16BIT;
    //     case 4:
    //         return (val & ALL_BITS_SET_32BIT) == ALL_BITS_SET_32BIT;
    //     case 8:
    //         return (val & ALL_BITS_SET_64BIT) == ALL_BITS_SET_64BIT;
    //     default:
    //         assert(false);
    //         return false;
    // }
}

template <typename T>
inline __host__ __device__ T
getAllBitsSet()
{
    // TODO
    return ~static_cast<T>(0);
    // Determine the size of the type at compile-time
    // constexpr int typeSize = sizeof(T);
    // switch (typeSize)
    // {
    //     case 1:
    //         return ALL_BITS_SET_8BIT;
    //     case 2:
    //         return ALL_BITS_SET_16BIT;
    //     case 4:
    //         return ALL_BITS_SET_32BIT;
    //     case 8:
    //         return ALL_BITS_SET_64BIT;
    //     default:
    //         assert(false);
    //         return 0;
    // }
}

/* TODO: universal hash family check */
template <typename T>
inline __host__ __device__ __uint32_t
xxhash32(T value, int seed)
{
    __uint32_t h32 = seed + 0x9e3779b9;
    value *= 0x85ebca6b;
    value ^= value >> 13;
    value *= 0xc2b2ae35;
    value ^= value >> 16;
    h32 += value * 0x9e3779b9;
    h32 ^= h32 >> 16;
    h32 *= 0x85ebca6b;
    h32 ^= h32 >> 13;
    return h32;
}

template <typename T>
inline __host__ __device__ __uint32_t
xxhash32_simp(T value, int seed)
{
    return seed ^ value;
}


inline __host__ __device__ int gcd(int a, int b) {
    // Ensure that a is non-negative
    a = abs(a);
    b = abs(b);

    while (b != 0) {
        int temp = b;
        b = a % b; // Get the remainder
        a = temp;  // Update a
    }
    return a; // GCD is found in a
}

size_t get_maximum_shared_memory_per_block() {
    int deviceId;
    cudaGetDevice(&deviceId);

    // Get properties of the device
    cudaDeviceProp deviceProp;
    cudaGetDeviceProperties(&deviceProp, deviceId);

    // Determine the maximum shared memory per block
    return deviceProp.sharedMemPerBlock;
}

int get_GPU_SM_count() {
    int deviceId;
    cudaGetDevice(&deviceId);

    // Get properties of the device
    cudaDeviceProp deviceProp;
    cudaGetDeviceProperties(&deviceProp, deviceId);

    // Determine the maximum shared memory per block
    return deviceProp.multiProcessorCount ;
}