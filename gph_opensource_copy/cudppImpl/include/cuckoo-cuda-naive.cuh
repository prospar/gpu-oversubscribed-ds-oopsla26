#ifndef _CUCKOO_CUDA_NAIVE_HPP_
#define _CUCKOO_CUDA_NAIVE_HPP_

#include <iostream>
#include <iomanip>
#include <vector>
#include <cmath>
#include <cstdlib>
#include "common.h"
#include "Exp_batch_result_holder.cuh"

/**
 * Cuckoo hash table generic class.
 */
template <typename T>
class CuckooHashTableCuda_Naive
{
protected:
    /** Input parameters. */
    const uint32_t _size; //!< size of one hash table. By default, we have four hash table.
    const int _num_funcs;

    uint32_t *_d_failures; //!< Device memory: General use error flag.

    /** Actual data table. */
    Entry *_data; //!< Device memory: The hash table contenst.

    /** Cuckoo hash function set. */
    Functions<2> constants_2_; //!< Constants for a set of two hash functions.
    Functions<3> constants_3_; //!< Constants for a set of three hash functions.
    Functions<4> constants_4_; //!< Constants for a set of four hash functions.
    Functions<5> constants_5_; //!< Constants for a set of five hash functions.
public:
    /** Constructor & Destructor. */
    /**
     * @param max_table_entries # kv pair to be insert
     *
     */
    CuckooHashTableCuda_Naive(const int max_table_entries, const float space_usage, const int num_functions)
        : _size(static_cast<uint32_t>(  ceil(max_table_entries * space_usage)  )), _num_funcs(num_functions)
    {
        // _size(static_cast<uint32_t>(  ceil(max_table_entries * space_usage)  ))
        printf("constructor: _size %u _num_funcs %d\n", _size, _num_funcs);
        // Allocate memory
        cudaMalloc((void **)&_data, sizeof(Entry) * _size);
        cudaMalloc((void **)&_d_failures, sizeof(uint32_t));
        
        if (_num_funcs < 2 || _num_funcs > 5)
        {
            printf("Number of hash functions must be from 2 to 5; "
                   "others are unimplemented.");
            return;
        }
    };

    ~CuckooHashTableCuda_Naive()
    {
        cudaFree(_data);
        cudaFree(_d_failures);

        _data = NULL;
        _d_failures = NULL;
    };

    /** Supported operations. */
    int insert_vals(const T *const keys, const T *const vals, const uint32_t n);
    void lookup_vals(const T *const keys, T * vals, const uint32_t n);
};

//! Compute how long an eviction chain is allowed to become for a given input size.
/*!    \param[in] n       Number of keys in the input.
    *  \param[in] table_size     Number of slots in the hash table.
    *  \param[in] num_functions  Number of hash functions being used.
    *  \returns The number of iterations that should be allowed.
    *
    *  The latter two parameters are only needed when using an empirical
    *  formula for computing the chain length.
    */
uint32_t ComputeMaxIterations(const uint32_t n,
                              const uint32_t table_size,
                              const uint32_t num_functions)
{
    float lg_input_size = (float)(log2((double)n) / log2(2.0));

    // Use an empirical formula for determining what the maximum number of
    // iterations should be.  Works OK in most situations.
    float load_factor = float(n) / table_size;
    float ln_load_factor = (float)(log2(load_factor) / log2(2.71828183));

    uint32_t max_iterations = (uint32_t)(4.0 * ceil(-1.0 / (0.028255 + 1.1594772 * ln_load_factor) * lg_input_size));
    // return max_iterations;
    return 1000;
}

//! Computes the value of a hash function for a given key.
/*! \param[in] constants  Constants used by the hash function.
  ! \param[in] key        Key being hashed.
  ! \returns              The value of the hash function for the key.
 */
inline __device__ __host__
    uint32_t
    hash_function_inner(const uint2 constants,
                        const uint32_t key)
{
#if 1
    // Fast version.
    return ((constants.x ^ key) + constants.y) % kPrimeDivisor;
#else
    // Slow version.
    return ((unsigned long long)constants.x * key + constants.y) % kPrimeDivisor;
#endif
}

//! Computes the value of a hash function for a given key.
/*! \param[in] functions        All of the constants used by the hash functions.
  ! \param[in] which_function   Which hash function is being used.
  ! \param[in] key              Key being hashed.
  ! \returns                    The value of a hash function with a given key.
 */
template <unsigned kNumHashFunctions>
inline __device__ __host__
    uint32_t
    hash_function(const Functions<kNumHashFunctions> functions,
                  const uint32_t which_function,
                  const uint32_t key)
{
    return hash_function_inner(functions.constants[which_function], key);
}

//! Makes an 64-bit Entry out of a key-value pair for the hash table.
inline __device__ __host__ Entry make_entry(uint32_t key, uint32_t value)
{
    return (Entry(key) << 32) + value;
}
//! Returns the key of an Entry.
inline __device__ __host__ uint32_t get_key(Entry entry)
{
    return (uint32_t)(entry >> 32);
}
//! Returns the value of an Entry.
inline __device__ __host__ uint32_t get_value(Entry entry)
{
    return (uint32_t)(entry & 0xffffffff);
}

//! Determine where to insert the key next.  The hash functions are used in round-robin order.
template <unsigned kNumHashFunctions>
__device__ unsigned determine_next_location(const Functions<kNumHashFunctions> constants,
                                            const uint32_t table_size,
                                            const uint32_t key,
                                            const uint32_t previous_location)
{
    // Identify all possible locations for the entry.
    uint32_t locations[kNumHashFunctions];
#pragma unroll
    for (unsigned i = 0; i < kNumHashFunctions; ++i)
    {
        locations[i] = hash_function(constants, i, key) % table_size;
    }

    // Figure out where the item should be inserted next.
    uint32_t next_location = locations[0];
#pragma unroll
    for (int i = kNumHashFunctions - 2; i >= 0; --i)
    {
        next_location = (previous_location == locations[i] ? locations[i + 1]
                                                           : next_location);
    }
    return next_location;
}

//! Attempts to insert a single entry into the hash table.
/*! This process stops after a certain number of iterations.  If the thread is
    still holding onto an item because of an eviction, it tries the stash.
    If it fails to enter the stash, it returns false.
    Otherwise, it succeeds and returns true.
 */
template <unsigned kNumHashFunctions>
__device__ bool insert(const uint32_t table_size,
                       const Functions<kNumHashFunctions> constants,
                       const uint32_t max_iteration_attempts, // 就是之前用 ComputeMaxIterations 算的.
                       Entry *table,
                       Entry entry,
                       uint32_t *iterations_used)
{
    uint32_t key = get_key(entry);

    // The key is always inserted into its first slot at the start.
    uint32_t location = hash_function(constants, 0, key) % table_size; // 这边是先用第0个hash_function.

    // Keep inserting until an empty slot is found or the eviction chain grows too large.
    for (unsigned its = 1; its <= max_iteration_attempts; its++)
    {
        // Insert the new entry.
        entry = atomicExch(&table[location], entry);
        key = get_key(entry);

        // If no key was evicted, we're done.
        if (key == kKeyEmpty)
        {
            *iterations_used = its;
            break;
        }
        // Otherwise, determine where the evicted key will go.
        location = determine_next_location(constants, table_size, key, location);
    }
    if (key != kKeyEmpty)
    {
        return false;
    }
    return true;
}

/**
 *
 * Cuckoo: insert operation (kernel + host function).
 * Returns:
 *   Number of rehashings beneath.
 */
template <unsigned kNumHashFunctions>
__global__ void cuckooInsertKernel_Naive(const uint32_t n,
                                         const uint32_t *keys,
                                         const uint32_t *values,
                                         const uint32_t table_size,
                                         const Functions<kNumHashFunctions> constants,
                                         const uint32_t max_iteration_attempts,
                                         Entry *table,
                                         uint32_t *failures)
{
    // Check if this thread has an item and if any previous threads failed.
    unsigned thread_index = threadIdx.x +
                            blockIdx.x * blockDim.x +
                            blockIdx.y * blockDim.x * gridDim.x;

    if (thread_index >= n || *failures)
        return;

    Entry entry = make_entry(keys[thread_index], values[thread_index]);

    unsigned iterations = 0;
    bool success = insert<kNumHashFunctions>(table_size,
                                             constants,
                                             max_iteration_attempts,
                                             table,
                                             entry,
                                             &iterations);
    if (success == false)
    {
        *failures = 1;
    }
}

template <class T>
__global__ void clear_table(const uint32_t table_size,
                            const T value,
                            T *table)
{
    uint32_t thread_index = threadIdx.x +
                            blockIdx.x * blockDim.x +
                            blockIdx.y * blockDim.x * gridDim.x;
    if (thread_index < table_size)
    {
        table[thread_index] = value;
    }
}

template <typename T>
int CuckooHashTableCuda_Naive<T>::insert_vals(const T *const input_keys, const T *const input_vals, const uint32_t n)
{
    uint32_t max_iterations = ComputeMaxIterations(n, _size, static_cast<uint32_t>(_num_funcs));
    printf("max_iterations %u\n", max_iterations);
    T *d_keys;
    T *d_vals;

    cudaMalloc((void **)&d_keys, n * sizeof(T));
    cudaMalloc((void **)&d_vals, n * sizeof(T));

    cudaMemcpy(d_keys, input_keys, n * sizeof(T), cudaMemcpyHostToDevice);
    cudaMemcpy(d_vals, input_vals, n * sizeof(T), cudaMemcpyHostToDevice);

    uint32_t num_failures = 1;
    uint32_t num_attempts = 0;
    float total_insert_ms = 0; 

    while (num_failures && ++num_attempts < kMaxRestartAttempts)
    {
        if (_num_funcs == 2)
            constants_2_.Generate();
        else if (_num_funcs == 3)
            constants_3_.Generate();
        else if (_num_funcs == 4) 
            constants_4_.Generate();
        else
            constants_5_.Generate();
        // printf("content of constants_4_: \n");
        // for (int i = 0; i < 4; i++) {
        //     printf("x %u ", constants_4_.constants[i].x);
        //     printf("y %u\n", constants_4_.constants[i].y);
        // }
        
        clear_table<<<ComputeGridDim(_size), BLOCK_SIZE>>>(_size, kEntryEmpty, _data); // init content in each slot
        
        num_failures = 0;
        
        cudaMemset(_d_failures, 0, sizeof(uint32_t));
        
        TimerHelp timer("CUDPP insert");
        if (_num_funcs == 2)
        {
            cuckooInsertKernel_Naive<<<ComputeGridDim(n), BLOCK_SIZE>>>(n,
                                                                        d_keys,
                                                                        d_vals,
                                                                        _size,
                                                                        constants_2_,
                                                                        max_iterations,
                                                                        _data,
                                                                        _d_failures);
            total_insert_ms += timer.elapsed();
        }
        else if (_num_funcs == 3)
        {
            cuckooInsertKernel_Naive<<<ComputeGridDim(n), BLOCK_SIZE>>>(n,
                                                                        d_keys,
                                                                        d_vals,
                                                                        _size,
                                                                        constants_3_,
                                                                        max_iterations,
                                                                        _data,
                                                                        _d_failures);
            total_insert_ms += timer.elapsed();                                                            
        }
        else if (_num_funcs == 4)
        {
            cuckooInsertKernel_Naive<<<ComputeGridDim(n), BLOCK_SIZE>>>(n,
                                                                        d_keys,
                                                                        d_vals,
                                                                        _size,
                                                                        constants_4_,
                                                                        max_iterations,
                                                                        _data,
                                                                        _d_failures);
            total_insert_ms += timer.elapsed();
        }
        else
        {
            cuckooInsertKernel_Naive<<<ComputeGridDim(n), BLOCK_SIZE>>>(n,
                                                                        d_keys,
                                                                        d_vals,
                                                                        _size,
                                                                        constants_5_,
                                                                        max_iterations,
                                                                        _data,
                                                                        _d_failures);
            total_insert_ms += timer.elapsed();
        }
        // Check if successful.
        cudaMemcpy( &num_failures, _d_failures, sizeof(uint32_t), cudaMemcpyDeviceToHost );
    }

    if (num_attempts >= kMaxRestartAttempts) {
        printf("Needed %u attempts to build, but discard still exist\n", num_attempts);
    } else {
        printf("Needed %u attempts to build\n", num_attempts);
    }
    
    printf("TIMING: %.5f ms (CUDPP insert)\n", total_insert_ms);

    cudaFree(d_keys);
    cudaFree(d_vals);
    d_keys = NULL;
    d_vals = NULL;
    return num_attempts;
}
//! Determine where in the hash table the key could be located.
template <unsigned kNumHashFunctions>
__device__ void
KeyLocations(const Functions<kNumHashFunctions> constants,
             const unsigned  table_size,
             const unsigned  key,
                   unsigned  locations[kNumHashFunctions])
{
  // Compute all possible locations for the key in the big table.
  #pragma unroll
  for (int i = 0; i < kNumHashFunctions; ++i) {
    locations[i] = hash_function(constants, i, key) % table_size;
  }
}

//! Answers a single query.
/*! @ingroup PublicInterface
 *  @param[in]  key                   Query key
 *  @param[in]  table_size            Size of the hash table
 *  @param[in]  table                 The contents of the hash table
 *  @param[in]  constants             The hash functions used to build the table
 *  @returns The value of the query key, if the key exists in the table.  Otherwise, \ref kNotFound will be returned.
 */
template <unsigned kNumHashFunctions> __device__
uint32_t retrieve(const uint32_t                      query_key,
                  const uint32_t                      table_size,
                  const Entry                        *table,
                  const Functions<kNumHashFunctions>  constants)
{
  // Identify all of the locations that the key can be located in.
  uint32_t locations[kNumHashFunctions];
  KeyLocations(constants, table_size, query_key, locations); // potential global access

  // Check each location until the key is found.
  uint32_t num_probes = 1;
  Entry    entry      = table[locations[0]]; // one global access
  uint32_t key        = get_key(entry);

  #pragma unroll
  for (unsigned i = 1; i < kNumHashFunctions; ++i) {
    if (key != query_key && key != kNotFound) {
    // if (key != query_key) {
      num_probes++;
      entry = table[locations[i]];
      key = get_key(entry);
    }
  }
  if (get_key(entry) == query_key) {
    return get_value(entry);
  } else {
    return kNotFound;
  }
}


/**
 * Cuckoo: lookup operation (kernel + host function).
 */
template <unsigned kNumHashFunctions> __global__ 
void cuckooLookupKernel_Naive(const uint32_t n,
                              const uint32_t *query_keys,
                              const uint32_t table_size,
                              const Entry *table,
                              const Functions<kNumHashFunctions> constants,
                              uint32_t *values_out)
{
  // Get the key.
  uint32_t thread_index = threadIdx.x +
                          blockIdx.x * blockDim.x +
                          blockIdx.y * blockDim.x * gridDim.x;
  if (thread_index >= n)
    return;
  uint32_t key = query_keys[thread_index];
  
  values_out[thread_index] = retrieve<kNumHashFunctions>
                                     (key,
                                      table_size,
                                      table,
                                      constants);   
}


//! Query the hash table.
/*! @param[in] query_keys    Device memory array containing all of the query keys.   
*   @param[in] query_vals     Values for the query keys.
*   @param[in] n  Number of keys in the query set.
*
*  kNotFound is returned for any query key that failed to be found
*  in the table.
*/
template <typename T>
void CuckooHashTableCuda_Naive<T>::lookup_vals(const T * const query_keys, T * query_vals, const uint32_t n)
{
    T *d_keys;
    T *d_vals;

    cudaMalloc((void **)&d_keys, n * sizeof(T));
    cudaMalloc((void **)&d_vals, n * sizeof(T));
    
    cudaMemcpy(d_keys, query_keys, n * sizeof(T), cudaMemcpyHostToDevice);
    cudaMemset(d_vals, 0, sizeof(T) * n);
    
    {
        TimerHelp timer("CUDPP search");
        if (_num_funcs == 2) cuckooLookupKernel_Naive<<<ComputeGridDim(n), BLOCK_SIZE>>>(n, d_keys, _size, _data, constants_2_, d_vals);
        else if (_num_funcs == 3) cuckooLookupKernel_Naive<<<ComputeGridDim(n), BLOCK_SIZE>>>(n, d_keys, _size, _data, constants_3_, d_vals);
        else if (_num_funcs == 4) cuckooLookupKernel_Naive<<<ComputeGridDim(n), BLOCK_SIZE>>>(n, d_keys, _size, _data, constants_4_, d_vals);
        else cuckooLookupKernel_Naive<<<ComputeGridDim(n), BLOCK_SIZE>>>(n, d_keys, _size, _data, constants_5_, d_vals);
        timer.print();
    }

    cudaMemcpy(query_vals, d_vals, sizeof(T) * n, cudaMemcpyDeviceToHost);

    cudaFree(d_keys);
    cudaFree(d_vals);
    d_keys = NULL;
    d_vals = NULL;
}
#endif