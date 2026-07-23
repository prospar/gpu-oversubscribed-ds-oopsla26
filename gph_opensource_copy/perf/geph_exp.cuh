#pragma once
#include <unordered_set>

#include "./../ThirdParties/configor/include/configor/json.hpp"
#include "./../common/include/Exp_batch_result_holder.cuh"
#include "./../geph/include/GPHOS.cuh"
#include "experiments.cuh"

#include <fmt/color.h>
#include <fmt/core.h>

namespace geph_exp {
static size_t check(const uint32_t *keys_to_insert,
                    const uint32_t *vals_to_insert, const size_t insert_n,
                    const uint32_t *keys_to_find, const uint32_t *vals_to_check,
                    const size_t find_n, json::value &exp_res_object,
                    bool enable_quick_check = true) {
  size_t total_checked = 0;
  size_t correct_checked = 0;
  if (enable_quick_check) {
    for (int i = 0; i < find_n; i += (find_n / 100000)) {
      if (vals_to_check[i] == keys_to_find[i] + 1) {
        correct_checked += 1;
      }
      total_checked += 1;
    }
  } else {
    std::unordered_map<uint32_t, uint32_t> m;
    for (int i = 0; i < insert_n; i++) {
      m.insert({keys_to_insert[i], vals_to_insert[i]});
    }

    for (int i = 0; i < find_n; i += (find_n / 100000)) {
      total_checked += 1;
      auto ground_truth = m.find(keys_to_find[i]);
      if ((ground_truth == m.end()) && (vals_to_check[i] == 0)) {
        correct_checked += 1;
        // fmt::print("key {}, want {}, and {}\n", keys_to_find[i], "not exist", vals_to_check[i]);
      } else if ((ground_truth != m.end()) &&
                 (ground_truth->second == vals_to_check[i])) {
        correct_checked += 1;
        // fmt::print("key {}, want {}, and {}\n",  keys_to_find[i], ground_truth->second, vals_to_check[i]);
      } else {
        // if (ground_truth == m.end())
        // fmt::print("key {}, want {}, but {}\n", keys_to_find[i], "not exist", vals_to_check[i]);
        // else
        // fmt::print("key {}, want {}, but {}\n", keys_to_find[i], ground_truth->second, vals_to_check[i]);
      }
    }
  }

  exp_res_object["total_checked"] = fmt::format("{}", total_checked);
  exp_res_object["correct_checked"] = fmt::format("{}", correct_checked);
  fmt::print("Correctness: {}\n", correct_checked * 1.0 / total_checked);
  return total_checked - correct_checked;
}

void geph_find(uint32_t *keys_to_insert, uint32_t *vals_to_insert,
               size_t insert_n, uint32_t *keys_to_find, size_t find_n,
               Competitor_meta competitor_meta, float load_factor,
               json::value &exp_res_object, Time_recorder &time_recorder,
               bool do_check) {
  const int bucket_cap = 32;
  const int virtual_bucket_n = 8;
  const int lookup_group_size = 4;
  const int insert_group_size = 8;
  const int cell_length = 2 * 49152 * 80;
  const int rand_seed = 114515;

  uint64_t *dummy_array = nullptr;

  double bytes = 12.72 * 1024.0 * 1024.0 * 1024.0;
  size_t num_elements = static_cast<size_t>(bytes / sizeof(uint64_t));

  cudaError_t err = cudaMalloc(&dummy_array, num_elements * sizeof(uint64_t));
  if (err != cudaSuccess) {
    printf("CUDA malloc failed: %s\n", cudaGetErrorString(err));
    // Handle the error (e.g., free other memory, reduce allocation size, etc.)
  } else {
    printf("CUDA malloc succeeded\n");
  }

  int64_t table_max_cap = (int64_t)(insert_n / load_factor);
  int bucket_n = (int)(table_max_cap / bucket_cap);
  GPHOSGPUTable<uint64_t, bucket_cap, lookup_group_size, insert_group_size,
                virtual_bucket_n>
      hash_table(cell_length, bucket_n, rand_seed);
  float insert_time = 0.0f;
  int gpubatch = 100000000;
  uint32_t *check_h = new uint32_t[find_n];
  uint64_t *packed_kv;
  cudaMallocManaged((void **)&packed_kv, sizeof(uint64_t) * gpubatch);
  uint32_t cpu_counter = 0;
  while (cpu_counter < insert_n) {
    int per_batch_ins = 0;
    while (per_batch_ins < gpubatch && cpu_counter < insert_n) {
      packed_kv[per_batch_ins] = combineKV<uint64_t>(
          keys_to_insert[cpu_counter], vals_to_insert[cpu_counter]);
      per_batch_ins++;
      cpu_counter++;
    }
    cudaMemAdvise(packed_kv, (gpubatch * sizeof(uint64_t)),
                  cudaMemAdviseSetAccessedBy, 0);
    cudaMemPrefetchAsync(packed_kv, (gpubatch * sizeof(uint64_t)), 0);
    UnifiedTimeRecorder recorder;

    vclog(INFO, "=== geph load factor {} ...", load_factor);

    hash_table.insert_key_values(packed_kv, per_batch_ins, &recorder);
    insert_time += recorder.get_timer_result("insert_kernel") / 1000.00;
    // fmt::print("Data insert complete\nTIMING: {} ms (geph total "
    //            "insert)\nthroughput: {} MOPS\n",
    //            recorder.get_timer_result("insert_kernel") / 1000.00);

    // fmt::print("Fill Phase\nTIMING: {} ms (geph fill insert)\n",
    //            recorder.get_timer_result("insert_kernel_fill_phase") / 1000.00);

    // fmt::print("Refinement Phase\nTIMING: {} ms (geph ref insert)\n",
    //            recorder.get_timer_result("insert_kernel_refine_phase") /
    //  1000.00);
  }

  std::cout << "Total time taken by insert kernel (ms): " << insert_time << "\n";

  //   //   stage 2 : find key
  //   hash_table.lookup_key_return_value_CSI(keys_to_find, check_h, find_n,
  //                                          &recorder);
  //   fmt::print("lookup throughput: {} MOPS\nTIMING: {} ms (geph search)\n\n",
  //              (find_n) / recorder.get_timer_result("lookup_kernel"),
  //              recorder.get_timer_result("lookup_kernel") / 1000.00);

  //   if (do_check) {
  //     check(keys_to_insert, vals_to_insert, insert_n, keys_to_find, check_h,
  //           find_n, exp_res_object);
  //   }
  if (check_h)
    delete[] check_h;
}

void geph_test_loadfactor(size_t insert_n, float load_factor,
                          json::value &exp_res_object,
                          Time_recorder &time_recorder) {
  const int bucket_cap = 32;
  const int virtual_bucket_n = 8;
  const int lookup_group_size = 4;
  const int insert_group_size = 8;
  const int cell_length = 2 * 49152 * 80;
  const int rand_seed = 114515;

  UnifiedTimeRecorder recorder;
  int64_t table_max_cap = (int64_t)(insert_n / load_factor);
  int bucket_n = (int)(table_max_cap / bucket_cap);

  // GPHOSGPUTable<uint64_t, bucket_cap, lookup_group_size, insert_group_size, virtual_bucket_n> hash_table(cell_length, bucket_n, rand_seed);

  // double tested_load_factor = hash_table.test_load_factor(100000000 * 0.0001, -1, &recorder);

  // vclog(INFO, "=== geph tested load factor \n{} (geph lf)\n", tested_load_factor);
  // fmt::print("=== geph tested load factor \n{} (geph lf)\n", tested_load_factor);

  int arr_n = bucket_n * bucket_cap;
  uint32_t *insert_arr = new uint32_t[arr_n];
  uint32_t *results = new uint32_t[arr_n];
  uint32_t *results_GPU = new uint32_t[arr_n];
  uint64_t *packed_kv = new uint64_t[arr_n];
  int fail_limit = 100000000 * 0.0001;

  uint64_t cur_elem = 0;
  for (int i = 0; i < arr_n; i++) {
    insert_arr[i] = ++cur_elem;
  }
  int seed = time(0);
  std::shuffle(insert_arr, insert_arr + arr_n,
               std::default_random_engine(seed));

  for (int i = 0; i < arr_n; i++) {
    results[i] = insert_arr[i] + 1;
    packed_kv[i] = combineKV<uint64_t>(insert_arr[i], results[i]);
  }

  int R = arr_n;
  int L = 1000;
  int binary_search_round = 8;
  assert(R > L);

  int insert_batch_size = (R + L) / 2;
  while (binary_search_round-- > 0) {
    bool getlower = false;
    GPHOSGPUTable<uint64_t, bucket_cap, lookup_group_size, insert_group_size,
                  virtual_bucket_n>
        hash_table(cell_length, bucket_n, rand_seed);

    UnifiedTimeRecorder recorder;
    hash_table.insert_key_values(packed_kv, insert_batch_size, &recorder);
    fmt::print("binary_search_round left {}\n", binary_search_round);
    fmt::print("\tData insert complete \nTIMING: {} ms (geph total insert)\n",
               recorder.get_timer_result("insert_kernel") / 1000.00);

    fmt::print("\tData insert complete \nTIMING: {} ms (geph fill insert)\n",
               recorder.get_timer_result("insert_kernel_fill_phase") / 1000.00);

    fmt::print("\tData insert complete \nTIMING: {} ms (geph refine insert)\n",
               recorder.get_timer_result("insert_kernel_refine_phase") /
                   1000.00);

    hash_table.lookup_key_return_value_CSI(insert_arr, results_GPU,
                                           insert_batch_size, nullptr);
    int error_cnt = 0;
    int valid_cnt = 0;
    for (int valid_i = 0; valid_i < insert_batch_size; valid_i++) {
      if (results_GPU[valid_i] != (insert_arr[valid_i] + 1)) {
        error_cnt++;
        if (error_cnt >= fail_limit) {
          getlower = true;
          break;
        }
      } else
        valid_cnt++;
    }
    if (getlower) {
      vclog(INFO,
            "Test load factor: left round {}, insert {} kvs causes {} error "
            "(limit {}), get lower",
            binary_search_round, insert_batch_size, error_cnt, fail_limit);
      insert_batch_size = (L + insert_batch_size) / 2;
    } else {
      vclog(INFO,
            "Test load factor: left round {}, insert {} kvs causes {} error "
            "(limit {}), get higher",
            binary_search_round, insert_batch_size, error_cnt, fail_limit);
      insert_batch_size = (insert_batch_size + R) / 2;
    }
  }
  double tested_load_factor = insert_batch_size * 1.0 / arr_n;

  vclog(INFO, "=== geph tested load factor \n{} (geph lf)\n",
        tested_load_factor);
  fmt::print("=== geph tested load factor \n{} (geph lf)\n",
             tested_load_factor);

  delete[] insert_arr;
  delete[] results;
  delete[] results_GPU;
  delete[] packed_kv;
}
} // namespace geph_exp