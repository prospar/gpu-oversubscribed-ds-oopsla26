/** This file defines all project-wide immutable constants */

#pragma once

#include <cstdint>
#include <semaphore.h>
#include <string>
#include <thread>

#define HASH_TAB_SIZE 100000
#define WARP_SIZE 32
#define SLAB_NODE_SIZE WARP_SIZE

using std::string;

/** Random number generation */
static constexpr uint64_t RANDOM_SEED = 42;
static constexpr uint32_t BlockSize = 512;

/** Number of buckets in the hash table */
static const uint32_t bucket_count = 1000;
static constexpr uint64_t MAX_OPERATIONS = 1e9;
static const uint32_t SENTINEL_KEY = 0;
static const uint32_t SENTINEL_VALUE = 0;
static const uint32_t PRIME_DIVISOR = 4294967291u;

// Keep a few CPU threads free to handle the page fault by GPU, batching, and to
// launch kernels.
static const uint32_t NUM_THREADS = std::thread::hardware_concurrency() - 3;

static const uint64_t SENTINEL_PAIR = 0;
/** Tombstone to identify deleted keys */
static const uint32_t TOMBSTONE_KEY = UINT32_MAX;
static const uint32_t TOMBSTONE_VALUE = UINT32_MAX;
/** Double the size of hash table when size reaches loadFactor*capacity */
const float LOAD_FACTOR = 0.9F;

// Constants for prefetching
// prefetching distance, tune by running experiments
const int PDIST = 4;
const int BLOCKDIMX = blockDim.x;

// Environment variable name for trace location
static const string PROJECT_ROOT_DIR = "TRACE_ROOT";

static const uint32_t MAX_PROBING_RETRIES = (1 << 30);
const uint64_t PROBE_RETRIES = (~uint64_t(0) - 1024);

static const uint32_t EMPTY_RANGE = UINT32_MAX;
static const uint32_t EMPTY_UNIQUE_COUNT = 0;

// LATER: SB: Is there a better way to define this?
#ifndef COOP_GROUP_SIZE
#define COOP_GROUP_SIZE 16
#endif

// batch size const for skip list
const uint32_t SL_BATCH_SIZE = 500000000;
static const string SL_TRACE_ROOT = "SL_TRACE_ROOT";

static constexpr size_t GiB = 1ULL << 30;       // 1 073 741 824 bytes
static constexpr size_t AVAIL_MEM = 4ULL * GiB; // keep 4 GiB free