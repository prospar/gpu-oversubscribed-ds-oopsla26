#ifndef _COMMON_H_
#define _COMMON_H_

#include <vector_types.h>
#include <cstdint>
#include "mt19937ar.h"

/** CUDA naive thread block size. */
// #define BLOCK_SIZE (64)
#define BLOCK_SIZE (512)

typedef unsigned long long Entry;                   //!< A key and its value are stored in a 64-bit number.  The key is stored in the upper 32 bits.

const uint32_t kMaxRestartAttempts = 20;            //!< Number of build attempts.
const uint32_t kKeyEmpty           = 0xffffffffu;   //!< Signifies empty slots in the table.
const unsigned kNotFound           = 0xffffffffu;   //!< Signifies that a query key was not found.

//! Value indicating that a hash table slot has no valid item within it.
const Entry    kEntryEmpty         = Entry(kKeyEmpty) << 32;

//! Prime number larger than the largest practical hash table size.
const unsigned kPrimeDivisor = 4294967291u;

template <unsigned N>
struct Functions {
  //! The constants required for all of the hash functions, including the stash.  Each function requires 2.
  uint2 constants[N];

  //! Generate new hash function constants.
  /*! The parameters are only used for debugging and examining the key distribution.
      \param[in] num_keys   Debug: Number of keys in the input.
      \param[in] d_keys     Debug: Device array of the input keys.
      \param[in] table_size Debug: Size of the hash table.
  */
  void Generate() {
    bool regenerate = true;

    while (regenerate) {
        regenerate = false;

        // Generate a set of hash function constants for this build attempt.
        for (unsigned i = 0 ; i < N; ++i) { // N = number of hash function to be generated. 
        unsigned new_a = genrand_int32() % kPrimeDivisor;
        constants[i].x = (1 > new_a ? 1 : new_a); // 这边就是说如果 new_a = 0, 那么就让constants[i].x = 1
        constants[i].y = genrand_int32() % kPrimeDivisor;
        }
    }
  }
};



//! Number of blocks to put along each axis of the grid.
const unsigned kGridSize  = 16384;

//! @name Internal
/// @{
dim3 ComputeGridDim(uint32_t n) {
    // Round up in order to make sure all items are hashed in.
    dim3 grid( (n + BLOCK_SIZE-1) / BLOCK_SIZE );
    if (grid.x > kGridSize) {
        grid.y = (grid.x + kGridSize - 1) / kGridSize;
        grid.x = kGridSize;
    }
    return grid;
}

#endif
