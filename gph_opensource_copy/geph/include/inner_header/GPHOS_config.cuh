// global constant that could change
#pragma once

#define CYCULAR_MOVE_ENABLED
#define CROSS_SM_INDEX
#define NO_BLOCK_LIMIT_CSI
// #define ONE_SUBTABLE_PER_SM
// #define CUCKOO_VIRTUAL_BUCKETS

// This is for GPU insert debug options
#define ONLY_DIRECT_INSERT 0
#define ALLOW_CIRCULAR_MOVE 1
#define ALLOW_CUCKOO_VIRTUAL_BUCKET 2

#define OUTPUT_INSERT_RESULT_COUNT


#define SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE (49152*2)

// cell split related
#define MAX_ALLOW_CELL_SPLIT_LEVEL 3
#define MAX_CONCURRENT_CELL_SPLIT                                             \
  4 // the reinsert buffer size = MAX_CONCURRENT_CELL_SPLIT * virtual_bucket_n
    // * bucket_capacity
#define MAX_INSERT_TRIGGERED_FACTOR                                           \
  64 // during a insertion, at most  MAX_INSERT_TRIGGERED_FACTOR * insert_n
     // insert is triggered

#define _HASH_T xxhash32
#define _HASH_int xxhash32<int>

#define BEST_CONFLICT_LIMIT 0.01

// L2_AS_FAST_MEMORY related
#define SETASIDE_L2_PERCENTAGE 0.75

// CSI and OSPS related
// #define _BLOCK_COUNT 131072
// #define _BLOCK_COUNT (32768)
#define BLOCK_COUNT 33280

// #define DISABLE_VECTORIZATION_AND_INSTRUCTION_PARALLEL
#define NKPR

// #define TRY_AVOID_VB_CONFLICT

// Insert related
typedef unsigned LOCK_T;

typedef __uint8_t CELL_T;

#define GPHOS_BLOCK_SIZE 512
#define MAX_RANDOM_SEED_TRY_ROUND 10000000

// #define CELL_SPLIT_ENABLED



//#define TEMP_CELL_IN_GLOBAL
