#include "functions.h"
#include <cstdint>
#include <iostream>
#include <typeinfo>

#if defined(FIXED_INDEX)
#include "skiplist_gfsl_fixed_index.cuh"
#elif defined(UNSORTED_IMPL)
#include "skiplist_gfsl_unsorted.cuh"
#elif defined(SEPARATE_POOL)
#include "skiplist_gfsl_separate_pool.cuh"
// #elif defined(BUSY_WAIT)
// #include "skiplist_gfsl_waiting.cuh"
#else
#include "skiplist_gfsl_kmer.cuh"
#endif

// #if defined(PREDECESSOR_SEARCH)
// #include "skiplist_gfsl_range.cuh"
// #endif
typedef unsigned uint32_t;
typedef unsigned long long _ull;

using SparseGFSL = struct SparseGFSL {
  uint32_t range;
  uint32_t unique_keys;
  uint32_t minKey;
  uint32_t maxKey;
  GFSL *innerGFSL;
};

SparseGFSL *createSparseGFSL(uint32_t outerSlots, uint32_t keysPerSkiplist) {
  SparseGFSL *sGFSLPtr = nullptr;
  cudaCheckErrorMacro(
      cudaMallocManaged((void **)&(sGFSLPtr), outerSlots * sizeof(SparseGFSL)),
      "Mem allocations failure for outer slots of GFSL");
  uint64_t nodesPerSkiplist =
      (1 << keysPerSkiplist) / 15 + 33; // nodes for each level
  cout << "[Info] Total skiplists: " << outerSlots << " with "
       << nodesPerSkiplist << " nodes per skiplist\n";
  for (uint32_t i = 0; i < outerSlots; i++) {
    // sGFSLPtr[i].range = 0;
    // sGFSLPtr[i].unique_keys = 0;
    sGFSLPtr[i].minKey = UINT32_MAX;
    cudaCheckErrorMacro(
        cudaMallocManaged(&sGFSLPtr[i].innerGFSL, sizeof(GFSL)),
        "[Error] Mem allocations failure for inner GFSL of SparseGFSL index");
    Chunk *nodesPool;
    uint64_t reqSize = nodesPerSkiplist;
#if defined(FIXED_INDEX)
    reqSize = nodesPerSkiplist * 0.9;
    cudaCheckErrorMacro(cudaMallocManaged(&nodesPool, sizeof(Chunk) * reqSize),
                        "[Error] Mem allocations failed for inner sl nodes");
#elif defined(UNSORTED_IMPL)
    cudaCheckErrorMacro(cudaMallocManaged(&nodesPool, sizeof(Chunk) * reqSize),
                        "[Error] Mem allocations failed for inner sl nodes");
#elif defined(SEPARATE_POOL)
    reqSize = nodesPerSkiplist * 0.9;
    cudaCheckErrorMacro(cudaMallocManaged(&nodesPool, sizeof(Chunk) * reqSize),
                        "[Error] Mem allocations failed for inner sl nodes");
// #elif defined(BUSY_WAIT)
//     cudaCheckErrorMacro(cudaMallocManaged(&nodesPool, sizeof(Chunk) * reqSize),
//                         "[Error] Mem allocations failed for inner sl nodes");
#else
    cudaCheckErrorMacro(cudaMallocManaged(&nodesPool, sizeof(Chunk) * reqSize),
                        "[Error] Mem allocations failed for inner sl nodes");
#endif
    // cudaCheckErrorMacro(
    //     cudaMallocManaged(&nodesPool, sizeof(Chunk) * nodesPerSkiplist),
    //     "[Error] Mem allocations failed for inner sl nodes");
    sGFSLPtr[i].innerGFSL->memory_pool = nodesPool;
#if defined(UVM_PREFETCH_HINT)
    cudaCheckErrorMacro(cudaMemPrefetchAsync(sGFSLPtr[i].innerGFSL->memory_pool,
                                             sizeof(Chunk) * reqSize, 0),
                        "[Error] Prefetch hint for memory pool failed");
#endif
#if defined(FIXED_INDEX)
    sGFSLPtr[i].innerGFSL->initializeGFSL((1 << keysPerSkiplist) / 14, 0.1,
                                          false);
#elif defined(UNSORTED_IMPL)
    sGFSLPtr[i].innerGFSL->initializeGFSL((1 << keysPerSkiplist) / 14, false);
#elif defined(SEPARATE_POOL)
    sGFSLPtr[i].innerGFSL->initializeGFSL((1 << keysPerSkiplist) / 14, 0.1,
                                          false);
// #elif defined(BUSY_WAIT)
//     sGFSLPtr[i].innerGFSL->initializeGFSL((1 << keysPerSkiplist) / 14, false);
#else
    sGFSLPtr[i].innerGFSL->initializeGFSL((1 << keysPerSkiplist) / 14, false);
#endif
    // sGFSLPtr[i].innerGFSL->initializeGFSL((1 << keysPerSkiplist) / 14, false);
    // Later add memory hint
  }
  cout << "[Info] Initialization completed for hetero skiplist\n";

  return sGFSLPtr;
}

bool freeSGFSL(SparseGFSL *sGFSLPtr, uint32_t outerSlots) {
  for (uint32_t ind = 0; ind < outerSlots; ind++) {
    sGFSLPtr[ind].innerGFSL->freeGFSL();
  }
  return true;
}

void printSparseGFSL(SparseGFSL *sGFSLPtr, uint32_t outerSlots) {
  for (uint32_t ind = 0; ind < outerSlots; ind++) {
    cout << "Skiplist :" << ind << " ";
    sGFSLPtr[ind].innerGFSL->print(true);
  }
}
