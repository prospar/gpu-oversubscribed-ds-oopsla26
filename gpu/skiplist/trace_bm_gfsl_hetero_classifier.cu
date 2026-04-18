// compilation command: nvcc -O3 -use_fast_math -lineinfo -std=c++17 -arch=sm_70 trace_bm_gfsl_hetero_classifier.cu -o hetero_classifier_driver -I../../include
// -rns=21
#include "constants.h"
#include "datatypes.h"
#include "functions.h"
#include "global-vars.h"
#include "skiplist_stats.cuh"

#include <algorithm>
#include <assert.h>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <execution>
#include <iostream>
#include <memory>
#include <set>
#include <thrust/execution_policy.h>
#include <thrust/sort.h>

#include "skiplist_gfsl_hetero.cuh"
#include "skiplist_gfsl_range.cuh"

using namespace std;

using HRClock = std::chrono::high_resolution_clock;
using DurationFloatMS = std::chrono::duration<float, std::milli>;

#define EMPTY_KEY 0xFFFFFFFFu
#define MAX_HITS 8
#define K 16
// skiplist kernels
__global__ void batch_insert(uint64_t numWarps, uint64_t len,
                             SparseGFSL *sparseSL, KeyValue *keyValList,
                             uint32_t *resList, uint32_t perSLRange,
                             GFSLRange *rangeGFSL, SkiplistStats *stats) {
  size_t tid = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
  size_t warpId = tid >> 5;

  for (uint64_t i = warpId; i < len; i += numWarps) {
    int slot = keyValList[i].key >> perSLRange;
    atomicExch(&(sparseSL[slot].range), slot + 1);
#if defined(PREDECESSOR_SEARCH)
    if (sparseSL[slot].range)
      rangeGFSL->insert((uint32_t)slot, 1, stats);
#endif
    resList[i] = sparseSL[slot].innerGFSL->insert(keyValList[i].key,
                                                  keyValList[i].value, stats);
    // Enable based on predecessor query
#if defined(PREDECESSOR_SEARCH)
    if (resList[i]) {
      if (sparseSL[slot].minKey > keyValList[i].key) {
        atomicMin(&(sparseSL[slot].minKey), keyValList[i].key);
      }
      if (sparseSL[slot].maxKey < keyValList[i].key) {
        atomicMax(&(sparseSL[slot].maxKey), keyValList[i].key);
      }
    }
#endif
  }
}

__global__ void batch_contains(uint64_t numWarps, uint64_t len,
                               SparseGFSL *skiplist, uint32_t *keyList,
                               uint32_t *resList, uint32_t perSLRange,
                               SkiplistStats *stats) {
  size_t tid = (size_t)(threadIdx.x + blockIdx.x * blockDim.x);
  uint64_t warpId = tid >> 5;

  for (uint64_t i = warpId; i < len; i += numWarps) {
    int slot = keyList[i] >> perSLRange;
    if (skiplist[slot].range)
      resList[i] =
          skiplist[slot].innerGFSL->contains(keyList[i], stats).kv.value;
    else
      resList[i] = (uint32_t)(-1);
  }
}

int cmp(const void *a, const void *b) {
  uint32_t x = *(const uint32_t *)a;
  uint32_t y = *(const uint32_t *)b;
  return (x > y) - (x < y);
}

size_t count_unique(uint32_t *arr, size_t n) {
  if (n == 0)
    return 0;

  qsort(arr, n, sizeof(uint32_t), cmp);

  size_t count = 1;
  for (size_t i = 1; i < n; i++) {
    if (arr[i] != arr[i - 1]) {
      count++;
    }
  }
  return count;
}

// Encode each dna base
// ===================================
//             ENCODE DNA
// ===================================

uint8_t encode_base(char c) {
  switch (c) {
  case 'A':
    return 0;
  case 'C':
    return 1;
  case 'G':
    return 2;
  case 'T':
    return 3;
  default:
    return 0;
  }
}

std::vector<uint8_t> encode_dna(const std::string &seq) {
  std::vector<uint8_t> out(seq.size());
  for (size_t i = 0; i < seq.size(); i++)
    out[i] = encode_base(seq[i]);
  return out;
}

// ===============================
//          FASTA LOADER
// ===============================

std::string load_fasta(const std::string &path) {
  std::ifstream file(path);
  std::string line, seq;
  while (std::getline(file, line)) {
    if (line.empty() || line[0] == '>')
      continue;
    seq += line;
  }
  return seq;
}

// ==================================
//         BUILD 11-MER KEY
// ==================================

uint32_t build_kmer_key_host(const uint8_t *genome, size_t pos) {
  uint32_t key = 0;
  for (int i = 0; i < K; i++) {
    key = (key << 2) | genome[pos + i];
  }
  return key;
}

void generate_random_lookup_keys(const uint8_t *genome, size_t genome_len,
                                 std::vector<uint32_t> &keys, size_t num_keys) {
  std::mt19937 rng(RANDOM_SEED); // fixed seed
  std::uniform_int_distribution<size_t> dist(1, genome_len - K);

  keys.resize(num_keys);

  for (size_t i = 0; i < num_keys; i++) {
    size_t pos = dist(rng);                     // random start position
    keys[i] = build_kmer_key_host(genome, pos); // encode k-mer
  }
}

int main(int argc, char *argv[]) {
  const uint32_t TAXON_ID = 562; // E. coli

  for (uint32_t i = 1; i < argc; i++) {
    if (parse_args(argv[i])) {
      std::cout << argv[i] << "\n";
      cerr << "[ERROR] Argument error, terminating run.\n";
      exit(EXIT_FAILURE);
    }
  }

  uint64_t *dummy_array = nullptr;
  constexpr uint64_t GiB = 1024ULL * 1024 * 1024;
  // reserve 1.6-50% 4-75% 5.6-100%
  uint64_t reserve_bytes =
      static_cast<uint64_t>(1 * double(GiB)); // change 2 to desired size
  size_t num_elements = reserve_bytes / sizeof(uint64_t);
  cudaError_t err = cudaMalloc(reinterpret_cast<void **>(&dummy_array),
                               num_elements * sizeof(uint64_t));
  if (err != cudaSuccess) {
    std::cerr << "cudaMalloc failed: " << cudaGetErrorString(err) << std::endl;
    return 1;
  } else {
    std::cout << "Successfully reserved ~ GiB of GPU memory (" << num_elements
              << " uint64_t elements)." << std::endl;
  }

  // Load genome (host ASCII)
  std::string genome_str =
      load_fasta("/data/heterods-trace/GCF_000001635.27_GRCm39_genomic.fna");
  size_t genome_len = genome_str.size();
  size_t num_kmers = genome_len - K + 1;

  size_t raw_capacity = static_cast<size_t>(num_kmers / LOAD_FACTOR);

  std::cout << "Genome length: " << genome_len << "\n";
  std::cout << "K-mers:        " << num_kmers << "\n";
  std::cout << "Total capacity:   " << raw_capacity << "\n";

  uint32_t outerSlots =
      std::ceil(static_cast<double>(UINT32_MAX - 1) / (1 << rangeSize));

  cout << "ADD: " << num_kmers << " OUTERSLOTS: " << outerSlots << " RANGE "
       << rangeSize << " Key per SL: " << (1 << rangeSize) << "\n";

  static simple_cached_allocator<KeyValue> alloc;

  // Cost across per-batch kernel launches
  float total_sort_time_insert = 0.0f;
  float total_sort_time_search = 0.0f;

  // Allocate memory for range skiplist prior to the main skiplist
  // allocation fails due to prefetching
  power_of_two = rangeSize;
  uint64_t elementsPerSkiplist = (1 << rangeSize);
  uint64_t totalSkiplists =
      (UINT32_MAX + elementsPerSkiplist - 1) / elementsPerSkiplist;
  uint64_t maxNodesRangeSL = (totalSkiplists / 14) + 32; // nodes for each level
  GFSLRange *rangeSkiplist = nullptr;
  GFSLRange *rangeSkiplistHost = new GFSLRange(maxNodesRangeSL, false);

  SparseGFSL *heteroSkiplist = createSparseGFSL(outerSlots, rangeSize);

  cudaCheckErrorMacro(cudaMalloc(&rangeSkiplist, sizeof(GFSLRange)),
                      "Mem allocation failed for range skiplist");
  cudaCheckErrorMacro(cudaMemcpy(rangeSkiplist, rangeSkiplistHost,
                                 sizeof(GFSLRange), cudaMemcpyHostToDevice),
                      "Mem copy failed for range skiplist");

  cudaCheckErrorMacro(
      cudaMemPrefetchAsync(heteroSkiplist, sizeof(SparseGFSL), 0),
      "Mem prefetch failed for UVM_PREFETCH_HINT");

  // TODO: Try memhint only on the half of the memory pool
  // Stats initilization to prevent incorrect node calculation
  SkiplistStats *stats;
  cudaMallocManaged(&stats, sizeof(SkiplistStats));
  new (stats) SkiplistStats(1);

  uint32_t *result = nullptr;
  cudaCheckErrorMacro(
      cudaMallocManaged((void **)&result, sizeof(uint32_t) * num_kmers),
      "Mem allocation failed for result");

  size_t cpu_counter = 0;
  uint32_t gpu_batch = 250000000;

  uint8_t *genome = new uint8_t[genome_len]; //encoded genome
  for (size_t i = 0; i < genome_len; i++)
    genome[i] = encode_base(genome_str[i]);

  cout << "Encoded genome loaded.\n";
  uint32_t *d_kmer_keys = new uint32_t[num_kmers];
  uint32_t *d_kmer_values = new uint32_t[num_kmers];

  for (size_t i = 0; i < num_kmers; i++) {
    d_kmer_keys[i] = build_kmer_key_host(genome, i);
    d_kmer_values[i] = TAXON_ID;
  }
  delete[] genome; // free garbage memory
  cout << "K-mer keys built.\n";

  KeyValue *d_uvm_batch;
  cudaCheckErrorMacro(
      cudaMallocManaged(&d_uvm_batch, sizeof(KeyValue) * gpu_batch),
      "Mem allocation for kmer batch failed");
  float insert_time = 0.0f;
  cudaEvent_t start, stop;
  cudaCheckErrorMacro(cudaEventCreate(&start),
                      "Event creation failed for start event");
  cudaCheckErrorMacro(cudaEventCreate(&stop),
                      "Event creation failed for stop event");
  std::cerr << "Starting insert of " << num_kmers << " elements\n";
  while (cpu_counter < num_kmers) {
    uint64_t per_batch_gpu_ins = 0;

    while (per_batch_gpu_ins < gpu_batch && cpu_counter < num_kmers) {
      d_uvm_batch[per_batch_gpu_ins].key = d_kmer_keys[cpu_counter];
      d_uvm_batch[per_batch_gpu_ins].value = d_kmer_values[cpu_counter];
      per_batch_gpu_ins++;
      cpu_counter++;
    }
    cudaCheckErrorMacro(cudaMemAdvise(d_uvm_batch,
                                      (per_batch_gpu_ins * sizeof(KeyValue)),
                                      cudaMemAdviseSetAccessedBy, 0),
                        "Mem advise hint failure for insert array");
    cudaCheckErrorMacro(
        cudaMemPrefetchAsync(d_uvm_batch,
                             (per_batch_gpu_ins * sizeof(KeyValue)), 0),
        "[Error]: Prefetch hint on batch of kmer keys");

    auto startSort = HRClock::now();
    thrust::sort(thrust::cuda::par(alloc), d_uvm_batch,
                 d_uvm_batch + per_batch_gpu_ins,
                 CompareByRangeShift(power_of_two));
    auto sortTimeInsert = HRClock::now() - startSort;
    total_sort_time_insert += DurationFloatMS(sortTimeInsert).count();

    NUM_BLOCKS = (gpu_batch + BLOCK_SIZE - 1) >> 4;
    cudaEventRecord(start);
    batch_insert<<<NUM_BLOCKS, BLOCK_SIZE>>>(
        NUM_BLOCKS * (BLOCK_SIZE >> 5), gpuBatchSize, heteroSkiplist,
        d_uvm_batch, result, rangeSize, rangeSkiplist, stats);
    cudaEventRecord(stop);

    cudaCheckErrorMacro(cudaDeviceSynchronize(), "Kmers Insert kernel failed");
#if defined(KEY_CHECK)
    for (uint32_t i = 0; i < gpuBatchSize; i++) {
      if (result[i] != 1) {
        std::cerr << "Something wrong with insert of " << i << " key "
                  << result[i] << "\n";
        std::cout << "[ERROR] Experiment terminated due to key check failure\n";
        exit(EXIT_FAILURE);
      }
    }
#endif

    float ms;
    cudaEventElapsedTime(&ms, start, stop);
    cout << "Inserted batch of " << per_batch_gpu_ins << " k-mers in " << ms
         << " ms\n";
    insert_time += ms;
  }

  std::cout << "Total build time (GPU): " << insert_time << " ms\n";
  std::cout << "Total sort time during insert (GPU): " << total_sort_time_insert
            << " ms\n";
  cout << "Starting classification phase...\n";

  std::string genome_str_find =
      load_fasta("/data/heterods-trace/GCF_000002285.3_CanFam3.1_genomic.fna");

  genome_len = genome_str_find.size();
  uint8_t *genome_find = new uint8_t[genome_len];
  for (size_t i = 0; i < genome_len; i++)
    genome_find[i] = encode_base(genome_str_find[i]);

  std::vector<uint32_t> h_keys_find;
  uint64_t num_keys = 1000000000;
  generate_random_lookup_keys(genome_find, genome_len, h_keys_find, num_keys);

  uint32_t *search_values;
  cudaMallocManaged(&search_values, sizeof(uint32_t) * gpu_batch);

  uint32_t *search_keys;
  cudaMallocManaged(&search_keys, sizeof(uint32_t) * gpu_batch);

  float search_time = 0.0f;
  cpu_counter = 0;
  while (cpu_counter < num_keys) {
    // Per-batch counter
    uint64_t per_batch_gpu_find = 0;

    while (per_batch_gpu_find < gpu_batch && cpu_counter < num_keys) {
      search_keys[per_batch_gpu_find] = h_keys_find[cpu_counter];
      per_batch_gpu_find++;
      cpu_counter++;
    }

    cudaCheckErrorMacro(
        cudaMemAdvise(search_keys, (per_batch_gpu_find * sizeof(uint32_t)),
                      cudaMemAdviseSetAccessedBy, 0),
        "Memadvise SetAccessedBy hint failure for search array");
    cudaCheckErrorMacro(
        cudaMemAdvise(search_values, (per_batch_gpu_find * sizeof(uint32_t)),
                      cudaMemAdviseSetAccessedBy, 0),
        "Memadvise SetAccessedBy hint failure for delete status");
    cudaCheckErrorMacro(
        cudaMemPrefetchAsync(search_keys,
                             (per_batch_gpu_find * sizeof(uint32_t)), 0),
        "Prefetching hint of the search array failed");
    cudaCheckErrorMacro(
        cudaMemPrefetchAsync(search_values,
                             (per_batch_gpu_find * sizeof(uint32_t)), 0),
        "Prefetching hint of the delete status failed");

    auto startSort = HRClock::now();
    thrust::sort(thrust::cuda::par(alloc), search_keys,
                 search_keys + per_batch_gpu_find,
                 CompareKeysByRangeShift(power_of_two));
    auto sortTimeInsert = HRClock::now() - startSort;
    total_sort_time_search += DurationFloatMS(sortTimeInsert).count();

    cudaEventRecord(start);
    batch_contains<<<NUM_BLOCKS, BLOCK_SIZE>>>(
        NUM_BLOCKS * (BLOCK_SIZE >> 5), per_batch_gpu_find, heteroSkiplist,
        search_keys, search_values, rangeSize, stats);
    cudaEventRecord(stop);

    cudaCheckErrorMacro(cudaDeviceSynchronize(),
                        "Kmers contains krenel failed");

    float ms;
    cudaEventElapsedTime(&ms, start, stop);
    cout << "Searched batch of " << per_batch_gpu_find << " k-mers in " << ms
         << " ms\n";
    search_time += ms;
  }
  cout << "Total search time (GPU): " << search_time << " ms\n";
  cout << "Total sort time during search (GPU): " << total_sort_time_search
       << " ms\n";
  for (size_t i = 0; i < num_keys; i++) {
    if (search_values[i] == 0) {
      std::cout << "It works!!!!!"
                << "\n";
      break;
    }
    // std::cout << "Read " << i << " → taxon " << search_values[i] << "\n";
  }
  alloc.reset();
  cudaCheckErrorMacro(cudaFree(d_uvm_batch),
                      "Mem free failed for kv batch after insertion");
  cudaCheckErrorMacro(cudaFree(result),
                      "Mem free failed for kv batch after insertion");

  // printSparseGFSL(heteroSkiplist, outerSlots); // implement
  freeSGFSL(heteroSkiplist, outerSlots); // replace by outerslots later
  cudaCheckErrorMacro(cudaFree(heteroSkiplist),
                      "Mem free failed for heteroSkiplist");
  cudaCheckErrorMacro(cudaFree(rangeSkiplist),
                      "Mem free failed for rangeSkiplist");

  std::cout << "[info] Experiment completed successfully\n";
  delete[] d_kmer_keys;
  cudaFree(d_uvm_batch);
  cudaFree(result);
  cudaFree(stats);
  cudaFree(search_keys);
  cudaFree(search_values);
  return 0;
}
