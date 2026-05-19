// compilation command: nvcc -O3 -use_fast_math -lineinfo -std=c++17 -arch=sm_70 kmer_counting.cu -o kmer_count -I../../include
#include "constants.h"
#include "datatypes.h"
#include "functions.h"
#include "global-vars.h"
#include "gpu_impl_UVM_CG_kmer.cuh"
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

using std::cerr;
using std::cout;
using std::endl;
using std::string;
using std::vector;

using HRClock = std::chrono::high_resolution_clock;
using DurationFloatMS = std::chrono::duration<float, std::milli>;

#define EMPTY_KEY 0xFFFFFFFFu
#define K 16

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

  // Load genome (host ASCII)
  std::string genome_str =
      load_fasta("/data/srinjoy/GCF_000001635.27_GRCm39_genomic.fna");

  size_t genome_len = genome_str.size();
  size_t num_kmers = genome_len - K + 1;

  const float LOAD_FACTOR = 0.9f;
  size_t raw_capacity = static_cast<size_t>(num_kmers / LOAD_FACTOR);
  size_t capacity = getCapacity(raw_capacity);
  std::cout << "Genome length: " << genome_len << "\n";
  std::cout << "K-mers:        " << num_kmers << "\n";
  std::cout << "HT capacity:   " << capacity << "\n";

  //   static simple_cached_allocator<uint32_t> alloc;
  size_t cpu_counter = 0;
  uint32_t gpu_batch = 100000000;

  uint8_t *genome = new uint8_t[genome_len];

  for (size_t i = 0; i < genome_len; i++)
    genome[i] = encode_base(genome_str[i]);

  uint64_t *dummy_array = nullptr;

  constexpr uint64_t GiB = 1024ULL * 1024 * 1024;
  uint64_t reserve_bytes = static_cast<uint64_t>(std::ceil(6.4 * GiB));
  size_t num_elements = reserve_bytes / sizeof(uint64_t);

  cudaError_t err = cudaMalloc(reinterpret_cast<void **>(&dummy_array),
                               num_elements * sizeof(uint64_t));

  if (err != cudaSuccess) {
    std::cerr << "cudaMalloc failed: " << cudaGetErrorString(err) << std::endl;
    return 1;
  } else {
    std::cout << "Successfully reserved ~4 GiB of GPU memory (" << num_elements
              << " uint64_t elements)." << std::endl;
  }

  auto *table = creategpuHash_UVM(capacity);

  cudaCheckErrorMacro(cudaMemAdvise(table, (capacity * sizeof(KeyValue)),
                                    cudaMemAdviseSetAccessedBy, 0),
                      "Mem advise hint failure for insert array");
  cudaCheckErrorMacro(
      cudaMemPrefetchAsync(table, (capacity * sizeof(KeyValue)), 0),
      "[Error]: Prefetch hint on batch of kmer keys");
  KeyValue *d_kmer_keys = new KeyValue[num_kmers];
  uint32_t *helper_arr = new uint32_t[num_kmers];

  for (size_t i = 0; i < num_kmers; i++) {
    d_kmer_keys[i].key = build_kmer_key_host(genome, i);
    helper_arr[i] = d_kmer_keys[i].key;
    d_kmer_keys[i].value = 0;
  }

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

      d_uvm_batch[per_batch_gpu_ins].key = d_kmer_keys[cpu_counter].key;
      d_uvm_batch[per_batch_gpu_ins].value = d_kmer_keys[cpu_counter].value;
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
    // thrust::sort(thrust::cuda::par(alloc), d_uvm_batch,
    //              d_uvm_batch + per_batch_gpu_ins,
    //              CompareByRangeShift(power_of_two));
    // Count k-mers
    insert_time += batch_insert_gpu_UVM_CG(table, d_uvm_batch,
                                           per_batch_gpu_ins, capacity);
    // cudaEventRecord(start);
    // // implement this kernel and call skiplist insert
    // count_kmer_kernel<<<NUM_BLOCKS, BLOCK_SIZE>>>(d_kmer_keys, num_kmers,
    //                                               table);
    // cudaEventRecord(stop);

    // cudaCheckErrorMacro(cudaDeviceSynchronize());

    // float ms;
    // cudaEventElapsedTime(&ms, start, stop);
  }
  std::cout << "K-mer count time (GPU): " << insert_time << " ms\n";

  // uint64_t count = count_unique(helper_arr, num_kmers);

  // verification
  // uint64_t unique = 0;
  // for (uint64_t i = 0; i < capacity; i++) {
  //   if (table[i].key != SENTINEL_KEY)
  //     unique++;
  // }

  // std::cout << "Unique k-mers inserted: " << count
  //           << "\tUnqiue k-mers in hashtable " << unique << "\n";

  return 0;
}
