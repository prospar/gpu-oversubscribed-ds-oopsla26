#include "constants.h"
#include "datatypes.h"
#include "functions.h"
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>

#include "global-vars.h"
#include "gpu_impl_UVM_CG.cuh"

#include <thrust/device_ptr.h>
#include <thrust/execution_policy.h>
#include <thrust/sort.h>

using std::cerr;
using std::cout;
using std::endl;
using std::string;
using std::vector;

using HRClock = std::chrono::high_resolution_clock;
using DurationFloatMS = std::chrono::duration<float, std::milli>;

#include <cuda_runtime.h>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#define EMPTY_KEY 0xFFFFFFFFu
#define MAX_HITS 8
#define K 16

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
    key = (key << 2) | (genome[pos + i] & 0x3);
  }
  return key;
}

// ===================================
//         READS TO K-MER KEYS
// ===================================
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

int main() {
  const uint32_t TAXON_ID = 562; // E. coli

  // --------------------------------------------------------
  // Load genome
  // --------------------------------------------------------
  std::string genome_str =
      load_fasta("/data/srinjoy/GCF_000001635.27_GRCm39_genomic.fna");

  size_t genome_len = genome_str.size();
  size_t num_kmers = genome_len - K + 1;

  const float LOAD_FACTOR = 0.9f;
  size_t raw_capacity = static_cast<size_t>(num_kmers / LOAD_FACTOR);
  size_t capacity = getCapacity(raw_capacity);

  std::cout << "Genome length: " << genome_len << "\n";
  std::cout << "k-mers:        " << num_kmers << "\n";
  std::cout << "Table cap:     " << capacity << "\n";

  // --------------------------------------------------------
  // Allocate genome (Unified Memory)
  // --------------------------------------------------------
  uint8_t *genome = new uint8_t[genome_len];

  for (size_t i = 0; i < genome_len; i++)
    genome[i] = encode_base(genome_str[i]);

  // --------------------------------------------------------
  // ALLOCATE DUMMY ARRAY
  // --------------------------------------------------------

  uint64_t *dummy_array = nullptr;

  constexpr uint64_t GiB = 1024ULL * 1024 * 1024;
uint64_t reserve_bytes =
    static_cast<uint64_t>(std::ceil(6.4 * GiB));
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

  // --------------------------------------------------------
  // Allocate hash table (Unified Memory)
  // --------------------------------------------------------

  auto *table = creategpuHash_UVM(capacity);

  cudaCheckErrorMacro(cudaMemAdvise(table, (capacity * sizeof(KeyValue)),
                                    cudaMemAdviseSetAccessedBy, 0),
                      "Memadvise::SetAccessedBy hint failed");
  cudaCheckErrorMacro(
      cudaMemPrefetchAsync(table, (capacity * sizeof(KeyValue)), 0),
      "Prefetching hint for the hash table failed");

  uint32_t *h_keys = new uint32_t[num_kmers];
  uint32_t *h_values = new uint32_t[num_kmers];

  for (size_t i = 0; i < num_kmers; i++) {
    h_keys[i] = build_kmer_key_host(genome, i);
    h_values[i] = TAXON_ID;
  }

  static simple_cached_allocator<KeyValue> alloc;
  size_t cpu_counter = 0;
  uint32_t gpu_batch = 100000000;
  KeyValue *d_uvm_batch;
  cudaMallocManaged(&d_uvm_batch, sizeof(KeyValue) * gpu_batch);

  float insert_time = 0.0f;
  while (cpu_counter < num_kmers) {
    uint64_t per_batch_gpu_ins = 0;

    while (per_batch_gpu_ins < gpu_batch && cpu_counter < num_kmers) {
      d_uvm_batch[per_batch_gpu_ins].key = h_keys[cpu_counter];
      d_uvm_batch[per_batch_gpu_ins].value = h_values[cpu_counter];
      per_batch_gpu_ins++;
      cpu_counter++;
    }

    cudaCheckErrorMacro(
        cudaMemAdvise(d_uvm_batch, (per_batch_gpu_ins * sizeof(KeyValue)),
                      cudaMemAdviseSetAccessedBy, 0),
        "Memadvise SetAccessedBy hint failure for insert array");
    cudaCheckErrorMacro(
        cudaMemPrefetchAsync(d_uvm_batch,
                             (per_batch_gpu_ins * sizeof(KeyValue)), 0),
        "Prefetching hint of the insert array failed");
    insert_time += batch_insert_gpu_UVM_CG(table, d_uvm_batch,
                                           per_batch_gpu_ins, capacity);
  }

  printf("Value of cpu counter: %lu\n", cpu_counter);
  // --------------------------------------------------------
  // Generate reads for classification
  // --------------------------------------------------------

  std::string genome_str_find =
      load_fasta("/data/srinjoy/GCF_000002285.3_CanFam3.1_genomic.fna");

  genome_len = genome_str_find.size();
  uint8_t *genome_find = new uint8_t[genome_len];
  for (size_t i = 0; i < genome_len; i++)
    genome_find[i] = encode_base(genome_str_find[i]);

  std::vector<uint32_t> h_keys_find;
  uint64_t num_keys = 1000000000;
  generate_random_lookup_keys(genome_find, genome_len, h_keys_find, num_keys);

  uint32_t *search_values;
  cudaMallocManaged(&search_values, sizeof(uint32_t) * num_keys);

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
    // auto start_find = HRClock::now();
    // thrust::sort(thrust::cuda::par(alloc), search_keys,
    //              search_keys + per_batch_gpu_find,
    //              CompareByRangeShiftDS(power_of_two));
    // auto end_find = HRClock::now();
    // DurationFloatMS duration_find = end_find - start_find;
    // search_time += duration_find.count();
    search_time += batch_lookup_gpu_UVM_CG(table, search_keys, search_values,
                                           per_batch_gpu_find, capacity);
  }

  // --------------------------------------------------------
  // Results
  // --------------------------------------------------------

  // uint64_t count = 0;
  // for (size_t i = 0; i < num_keys; i++) {
  //   if (search_values[i] != 0) {
  //     count++;
  //     // break;
  //   }
  //   // std::cout << "Read " << i << " → taxon " << search_values[i] << "\n";
  // }

  // cout << "Total matches of dog datset in mouse dataset : " << count << "\n";
  cout << "Total time taken for inserting mouse dataset : " << insert_time
       << " (ms)\n";
  cout << "Total time taken for searching dog dataset : " << search_time
       << " (ms)\n";
  // --------------------------------------------------------
  // Cleanup
  // --------------------------------------------------------
  delete[] genome;

  return 0;
}