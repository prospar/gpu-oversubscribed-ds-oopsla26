// compilation command: nvcc -O3 -use_fast_math -lineinfo -std=c++17 -arch=sm_70
// trace_bd_gfsl_kmer.cu -o kmer_count_driver -I../../include
#include "constants.h"
#include "datatypes.h"
#include "functions.h"
#include "global-vars.h"
#include "skiplist_stats.cuh"

#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>

#include <thrust/device_ptr.h>
#include <thrust/execution_policy.h>
#include <thrust/sort.h>

#include <cuda_runtime.h>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include "skiplist_gfsl_kmer.cuh"
using std::cerr;
using std::cout;
using std::endl;
using std::string;
using std::vector;

using HRClock = std::chrono::high_resolution_clock;
using DurationFloatMS = std::chrono::duration<float, std::milli>;

#define EMPTY_KEY 0xFFFFFFFFu
#define K 16
// skiplist kernels
__global__ void batch_insert(uint64_t numWarps, uint64_t len, GFSL *skiplist,
                             KeyValue *keyValList, uint32_t *resList,
                             SkiplistStats *stats) {
  size_t tid = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
  size_t warpId = tid >> 5;

  for (uint64_t i = warpId; i < len; i += numWarps) {
    resList[i] =
        skiplist->insert(keyValList[i].key, keyValList[i].value, stats);
  }
}

__global__ void findLastKey(GFSL *skiplist, uint32_t *resList) {
  resList[0] = skiplist->findLast();
}

__global__ void findFirstKey(GFSL *skiplist, uint32_t *resList) {
  resList[0] = skiplist->findFirst();
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

// driver function
int main(int argc, char **argv) {

  for (uint32_t i = 1; i < argc; i++) {
    if (parse_args(argv[i])) {
      std::cout << argv[i] << "\n";
      cerr << "[ERROR] Argument error, terminating run.\n";
      exit(EXIT_FAILURE);
    }
  }

  // uint64_t *dummy_array = nullptr;
  // constexpr uint64_t GiB = 1024ULL * 1024 * 1024;
  // // reserve 1.6-50% 4-75% 5.6-100%
  // uint64_t reserve_bytes =
  //     static_cast<uint64_t>(AVAIL_MEM); // change 2 to desired size
  // size_t num_elements = reserve_bytes / sizeof(uint64_t);
  // cudaError_t err = cudaMalloc(reinterpret_cast<void **>(&dummy_array),
  //                              num_elements * sizeof(uint64_t));
  // if (err != cudaSuccess) {
  //   std::cerr << "cudaMalloc failed: " << cudaGetErrorString(err) <<
  //   std::endl; return 1;
  // } else {
  //   std::cout << "Successfully reserved ~ GiB of GPU memory (" <<
  //   num_elements
  //             << " uint64_t elements)." << std::endl;
  // }

  std::vector<DeviceMemReservation> reservations;
  if (OVERSUB_RATIO) {
    reservations = query_and_reserve();
    cout << "Oversubscription enabled with ratio: " << OVERSUB_RATIO << "\n";
    printf("\n%-8s  %-8s  %-16s  %-16s\n", "Device", "Total", "Reserved",
           "Available");
    printf("%-8s  %-8s  %-16s  %-16s\n", "------", "-----", "--------",
           "--------");
    for (const auto &r : reservations) {
      printf("%-8d  %5.2f GiB  %12.2f GiB  %12.2f GiB\n", r.device_id,
             static_cast<double>(r.total_bytes) / GiB,
             static_cast<double>(r.reserved) / GiB,
             static_cast<double>(r.total_bytes - r.reserved) / GiB);
    }
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
  static simple_cached_allocator<KeyValue> alloc;
  // Cost across per-batch kernel launches
  float total_sort_time_insert = 0.0f;
  power_of_two = rangeSize;

  uint8_t *genome = new uint8_t[genome_len]; // encoded genome
  for (size_t i = 0; i < genome_len; i++)
    genome[i] = encode_base(genome_str[i]);
  cout << "Encoded genome loaded.\n";
  uint32_t *d_kmer_keys = new uint32_t[num_kmers];
  uint32_t *helper_arr = new uint32_t[num_kmers];

  for (size_t i = 0; i < num_kmers; i++) {
    d_kmer_keys[i] = build_kmer_key_host(genome, i);
    helper_arr[i] = d_kmer_keys[i];
  }
  delete[] genome;
  cout << "K-mer keys built.\n";

  GFSL *h_skiplist;
  uint32_t maxNodes = num_kmers / 14;
  cudaCheckErrorMacro(cudaMallocManaged(&h_skiplist, sizeof(GFSL)),
                      "Mem allocation failed for skiplist");
  Chunk *nodesPool;
  size_t reqSize = maxNodes + 33;
  cudaCheckErrorMacro(
      cudaMallocManaged((void **)&nodesPool, sizeof(Chunk) * reqSize),
      "Nodes memory allocation pool failure");
  h_skiplist->memory_pool = nodesPool;

  cudaCheckErrorMacro(cudaMemPrefetchAsync(h_skiplist, sizeof(GFSL), 0),
                      "Mem prefetch failed for UVM_PREFETCH_HINT");

  cudaCheckErrorMacro(cudaMemPrefetchAsync(h_skiplist->memory_pool,
                                           (sizeof(Chunk) * reqSize), 0),
                      "Prefetch hint error for memory pool");

  h_skiplist->initializeGFSL(maxNodes, false);
  SkiplistStats *stats;
  cudaMallocManaged(&stats, sizeof(SkiplistStats));
  new (stats) SkiplistStats(1);

  uint32_t *result = nullptr;
  cudaCheckErrorMacro(
      cudaMallocManaged((void **)&result, sizeof(uint32_t) * num_kmers),
      "Mem allocation failed for result");

  size_t cpu_counter = 0;
  uint32_t gpu_batch = 250000000;

  KeyValue *d_uvm_batch;
  cudaCheckErrorMacro(
      cudaMallocManaged(&d_uvm_batch, sizeof(KeyValue) * gpu_batch),
      "Mem allocation for kmer batch failed");
  float insert_time = 0.0f;
  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);

  while (cpu_counter < num_kmers) {
    uint64_t per_batch_gpu_ins = 0;

    while (per_batch_gpu_ins < gpu_batch && cpu_counter < num_kmers) {
      d_uvm_batch[per_batch_gpu_ins].key = d_kmer_keys[cpu_counter];
      d_uvm_batch[per_batch_gpu_ins].value = 0;
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

    // Count k-mers
    NUM_BLOCKS = (gpu_batch + BLOCK_SIZE - 1) >> 4;
    cudaEventRecord(start);

    batch_insert<<<NUM_BLOCKS, BLOCK_SIZE>>>(NUM_BLOCKS * (BLOCK_SIZE >> 5),
                                             per_batch_gpu_ins, h_skiplist,
                                             d_uvm_batch, result, stats);
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
  std::cout << "K-mer count time (GPU): " << insert_time << " ms\n";
  std::cout << "Total sort time during insert (GPU): " << total_sort_time_insert
            << " ms\n";

  // uint64_t count = count_unique(helper_arr, num_kmers);

  // // verification
  // uint64_t unique = 0;
  // for (uint64_t i = 0; i < gpu_outer_slot_size; i++) {
  //   for (uint32_t j = 0; j < inner_ht_slots; j++) {
  //     if (table[i].inner_hashtable[j].key != SENTINEL_KEY)
  //       unique++;
  //   }
  // }

  // std::cout << "Unique k-mers inserted: " << count
  //           << "\tUnqiue k-mers in hashtable " << unique << "\n";

  delete[](d_kmer_keys);
  delete[](helper_arr);
  cudaFree(d_uvm_batch);
  cudaFree(result);
  cudaFree(h_skiplist->memory_pool);
  cudaFree(h_skiplist);
  cudaFree(stats);

  if (OVERSUB_RATIO) {
    release_reservations(reservations);
  }
  return 0;
}
