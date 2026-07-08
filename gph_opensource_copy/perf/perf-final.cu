#include "./../common/include/Exp_batch_result_holder.cuh"
#include "experiments.cuh"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <fcntl.h>
#include <fmt/core.h>
#include <iostream>
#include <map>
#include <random>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <vector>

// #include "cudppimpl_naive_exp.cuh"
// #include "dycuckoo_exp.cuh"
// #include "warpcore_exp.cuh"
#include "geph_exp.cuh"

#include "perf-final-utils.cuh"

#define TRIAL_NUM 1

#include "competitors-experiments.cuh"

void run_exp_on_geph(std::string dataset_name, std::string pos, float lf = 0.5,
                     int expmode = EXP_MODE_CHECK) {
  DatasetManager data = DatasetManager(dataset_name, pos);

  size_t table_size =
      (size_t)(sizeof(uint32_t) * 2 * data.getInsertLen() / (lf));
  fmt::print("Table size {} GB\n", table_size * 1.0 / 1024 / 1024 / 1024);

  for (int trial = 1; trial <= TRIAL_NUM; trial++) {
    geph_uint32_experiment((size_t)table_size, data.getInsertKeys(),
                           data.getInsertVals(), data.getInsertLen(),
                           data.getDatasetName(), data.getLookupKeys(),
                           data.getLookupLen(), data.getWorkloadType(),
                           fmt::format("trial: {}", trial), expmode);
  }
}

void run_exp_on_geph_quick_check(std::string dataset_name, std::string pos,
                                 float lf = 0.5, int expmode = EXP_MODE_CHECK) {
  DatasetManager data = DatasetManager(dataset_name, pos);

//   data.enableQuickCheck();

  size_t table_size =
      (size_t)(sizeof(uint32_t) * 2 * data.getInsertLen() / (lf));
  fmt::print("Table size {} GB\n", table_size * 1.0 / 1024 / 1024 / 1024);

  for (int trial = 1; trial <= TRIAL_NUM; trial++) {
    geph_uint32_experiment((size_t)table_size, data.getInsertKeys(),
                           data.getInsertVals(), data.getInsertLen(),
                           data.getDatasetName(), data.getLookupKeys(),
                           data.getLookupLen(), data.getWorkloadType(),
                           fmt::format("trial: {}", trial), expmode);
  }
}

void run_exp_on_all_competitors(std::string dataset_name, std::string pos,
                                float lf = 0.5, int expmode = EXP_MODE_CHECK) {
  DatasetManager data = DatasetManager(dataset_name, pos);

  size_t table_size =
      (size_t)(sizeof(uint32_t) * 2 * data.getInsertLen() / (lf));
  fmt::print("Table size {} GB\n", table_size * 1.0 / 1024 / 1024 / 1024);

  // for (int trial = 1; trial <= TRIAL_NUM; trial++){
  //     cudppimpl_uint32_experiment(
  //         (size_t)table_size,
  //         data.getInsertKeys(), data.getInsertVals(), data.getInsertLen(), data.getDatasetName(),
  //         data.getLookupKeys(), data.getLookupLen(), data.getWorkloadType(),
  //         fmt::format("trial: {}", trial),
  //         expmode
  //     );
  // }

  // for (int trial = 1; trial <= TRIAL_NUM; trial++){
  //     dycuckoo_uint32_experiment(
  //         (size_t)table_size,
  //         data.getInsertKeys(), data.getInsertVals(), data.getInsertLen(), data.getDatasetName(),
  //         data.getLookupKeys(), data.getLookupLen(), data.getWorkloadType(),
  //         fmt::format("trial: {}", trial),
  //         expmode
  //     );
  // }

  // for (int trial = 1; trial <= TRIAL_NUM; trial++){
  //     warpcore_uint32_experiment(
  //         (size_t)table_size,
  //         data.getInsertKeys(), data.getInsertVals(), data.getInsertLen(), data.getDatasetName(),
  //         data.getLookupKeys(), data.getLookupLen(), data.getWorkloadType(),
  //         fmt::format("trial: {}", trial),
  //         expmode
  //     );
  // }

  for (int trial = 1; trial <= TRIAL_NUM; trial++) {
    geph_uint32_experiment((size_t)table_size, data.getInsertKeys(),
                           data.getInsertVals(), data.getInsertLen(),
                           data.getDatasetName(), data.getLookupKeys(),
                           data.getLookupLen(), data.getWorkloadType(),
                           fmt::format("trial: {}", trial), expmode);
  }
}

void run_exp_on_all_competitors_fix_table_size(std::string dataset_name,
                                               std::string pos,
                                               size_t table_size,
                                               int expmode = EXP_MODE_CHECK) {
  DatasetManager data = DatasetManager(dataset_name, pos);

  fmt::print("Table size {} GB\n", table_size * 1.0 / 1024 / 1024 / 1024);

  //     for (int trial = 1; trial <= TRIAL_NUM; trial++){
  //         cudppimpl_uint32_experiment(
  //             (size_t)table_size,
  //             data.getInsertKeys(), data.getInsertVals(), data.getInsertLen(), data.getDatasetName(),
  //             data.getLookupKeys(), data.getLookupLen(), data.getWorkloadType(),
  //             fmt::format("trial: {}", trial),
  //             expmode
  //         );
  //     }

  //     for (int trial = 1; trial <= TRIAL_NUM; trial++){
  //         dycuckoo_uint32_experiment(
  //             (size_t)table_size,
  //             data.getInsertKeys(), data.getInsertVals(), data.getInsertLen(), data.getDatasetName(),
  //             data.getLookupKeys(), data.getLookupLen(), data.getWorkloadType(),
  //             fmt::format("trial: {}", trial),
  //             expmode
  //         );
  //     }

  //     for (int trial = 1; trial <= TRIAL_NUM; trial++){
  //         warpcore_uint32_experiment(
  //             (size_t)table_size,
  //             data.getInsertKeys(), data.getInsertVals(), data.getInsertLen(), data.getDatasetName(),
  //             data.getLookupKeys(), data.getLookupLen(), data.getWorkloadType(),
  //             fmt::format("trial: {}", trial),
  //             expmode
  //         );
  //     }

  // for (int trial = 1; trial <= TRIAL_NUM; trial++){
  //     geph_uint32_experiment(
  //         (size_t)table_size,
  //         data.getInsertKeys(), data.getInsertVals(), data.getInsertLen(), data.getDatasetName(),
  //         data.getLookupKeys(), data.getLookupLen(), data.getWorkloadType(),
  //         fmt::format("trial: {}", trial),
  //         expmode
  //     );
  // }
  // }

  // void simple_test() {
  //     std::string dataset_name = "reddit";
  //     std::string workload_type = "none";

  //     size_t reddit_insert_len = 1000;
  //     uint32_t * reddit_insert_keys = new uint32_t[reddit_insert_len];
  //     uint32_t * reddit_insert_vals = new uint32_t[reddit_insert_len];
  //     for (uint32_t i = 0; i < reddit_insert_len; i++) {
  //         reddit_insert_keys[i] = i+1;
  //         reddit_insert_vals[i] = i+2;
  //     }
  //     size_t reddit_lookup_len = 2000;
  //     uint32_t * reddit_lookup_keys = new uint32_t[reddit_lookup_len];
  //     for (uint32_t i = 0; i < reddit_lookup_len; i++) {
  //         reddit_lookup_keys[i] = i+1;
  //     }

  //     cudppimpl_uint32_experiment(
  //         (size_t)4 * 1024 * 1024 * 1024, // 4GB
  //         reddit_insert_keys, reddit_insert_vals, reddit_insert_len, dataset_name,
  //         reddit_lookup_keys, reddit_lookup_len, workload_type,
  //         fmt::format(""),
  //         EXP_MODE_EFFECTIVE_LOAD_FACTOR_TEST
  //     );

  //     for (int trial = 1; trial <= TRIAL_NUM; trial++){
  //         cudppimpl_uint32_experiment(
  //             (size_t)4 * 1024 * 1024 * 1024, // 4GB
  //             reddit_insert_keys, reddit_insert_vals, reddit_insert_len, dataset_name,
  //             reddit_lookup_keys, reddit_lookup_len, workload_type,
  //             fmt::format("trial: {}", trial),
  //             EXP_MODE_CHECK
  //         );
  //     }

  //     dycuckoo_uint32_experiment(
  //         (size_t)4 * 1024 * 1024 * 1024, // 4GB
  //         reddit_insert_keys, reddit_insert_vals, reddit_insert_len, dataset_name,
  //         reddit_lookup_keys, reddit_lookup_len, workload_type,
  //         fmt::format(""),
  //         EXP_MODE_EFFECTIVE_LOAD_FACTOR_TEST
  //     );

  //     for (int trial = 1; trial <= TRIAL_NUM; trial++){
  //         dycuckoo_uint32_experiment(
  //             (size_t)4 * 1024 * 1024 * 1024, // 4GB
  //             reddit_insert_keys, reddit_insert_vals, reddit_insert_len, dataset_name,
  //             reddit_lookup_keys, reddit_lookup_len, workload_type,
  //             fmt::format("trial: {}", trial),
  //             EXP_MODE_CHECK
  //         );
  //     }

  // delete [] reddit_insert_keys;
  // delete [] reddit_lookup_keys;
  // delete [] reddit_insert_vals;
}

void LOOKUPTH_LF_COMP_DATASET() {
  for (float lf = 0.4; lf < 0.99; lf += 0.1) {
    run_exp_on_all_competitors("reddit", fmt::format("{}", 50), lf,
                               EXP_MODE_NO_CHECK);
    run_exp_on_all_competitors("lineitem", fmt::format("{}", 50), lf,
                               EXP_MODE_NO_CHECK);
    run_exp_on_all_competitors("random", fmt::format("{}", 50), lf,
                               EXP_MODE_NO_CHECK);
    run_exp_on_all_competitors("tao", fmt::format("{}", 50), lf,
                               EXP_MODE_NO_CHECK);
  }
}

void LOOKUPTH_TABLESIZE_COMP_DATASET() {
  size_t table_bytes = (size_t)(1.25 * 1024 * 1024 * 1024);
  for (int pos = 0; pos <= 100; pos += 25) {
    run_exp_on_all_competitors_fix_table_size("reddit", fmt::format("{}", pos),
                                              table_bytes, EXP_MODE_NO_CHECK);
    run_exp_on_all_competitors_fix_table_size(
        "lineitem", fmt::format("{}", pos), table_bytes, EXP_MODE_NO_CHECK);
    run_exp_on_all_competitors_fix_table_size("random", fmt::format("{}", pos),
                                              table_bytes, EXP_MODE_NO_CHECK);
    run_exp_on_all_competitors_fix_table_size("tao", fmt::format("{}", pos),
                                              table_bytes, EXP_MODE_NO_CHECK);
  }
}

void LOOKUPTH_POSITIVE_COMP_DATASET() {
  for (int pos = 0; pos <= 100; pos += 25) {
    run_exp_on_all_competitors("reddit", fmt::format("{}", pos), 0.7,
                               EXP_MODE_NO_CHECK);
    run_exp_on_all_competitors("lineitem", fmt::format("{}", pos), 0.7,
                               EXP_MODE_NO_CHECK);
    run_exp_on_all_competitors("random", fmt::format("{}", pos), 0.7,
                               EXP_MODE_NO_CHECK);
    run_exp_on_all_competitors("tao", fmt::format("{}", pos), 0.7,
                               EXP_MODE_NO_CHECK);
  }
}

void NCU_LOOKUPTH_LF_COMP() {
  for (float lf = 0.4; lf < 0.99; lf += 0.1) {
    run_exp_on_all_competitors("random", fmt::format("{}", 50), lf,
                               EXP_MODE_NO_CHECK);
  }
}

void NCU_LOOKUPTH_POSITIVE_COMP() {
  for (int pos = 0; pos <= 100; pos += 25) {
    run_exp_on_all_competitors("random", fmt::format("{}", pos), 0.7,
                               EXP_MODE_NO_CHECK);
  }
}

void NCU_MISC_BLOCKSIZE_COMP() {
  run_exp_on_all_competitors("random", fmt::format("{}", 50), 0.7,
                             EXP_MODE_NO_CHECK);
}

void AUTO_GEPH() {
  int auto_pos = 0;
  run_exp_on_geph_quick_check("random", fmt::format("{}", auto_pos), 0.7,
                              EXP_MODE_CHECK);
}

void AUTO_GEPH_LF_TEST() {
  size_t AUTO_COMP_table_bytes = (size_t)(2.0 * 1024 * 1024 * 1024);
  DatasetManager data = DatasetManager("random", "50");
  geph_uint32_experiment(
      AUTO_COMP_table_bytes, data.getInsertKeys(), data.getInsertVals(),
      data.getInsertLen(), data.getDatasetName(), data.getLookupKeys(),
      data.getLookupLen(), data.getWorkloadType(), fmt::format("trial: {}", 1),
      EXP_MODE_EFFECTIVE_LOAD_FACTOR_TEST);
}

#define COMP_CUDPP 0
#define COMP_WARPCORE 1
#define COMP_DYCUCKOO 2
#define COMP_GPH 3
void run_exp_on_single_competitors_fix_table_size(
    int comp, std::string dataset_name, std::string pos, size_t table_size,
    int expmode = EXP_MODE_CHECK) {
  DatasetManager data = DatasetManager(dataset_name, pos);

  fmt::print("Table size {} GB\n", table_size * 1.0 / 1024 / 1024 / 1024);

  // if (comp == COMP_CUDPP) {
  //     for (int trial = 1; trial <= TRIAL_NUM; trial++){
  //         cudppimpl_uint32_experiment(
  //             (size_t)table_size,
  //             data.getInsertKeys(), data.getInsertVals(), data.getInsertLen(), data.getDatasetName(),
  //             data.getLookupKeys(), data.getLookupLen(), data.getWorkloadType(),
  //             fmt::format("trial: {}", trial),
  //             expmode
  //         );
  //     }
  // }

  // if (comp == COMP_DYCUCKOO)
  // {
  //     for (int trial = 1; trial <= TRIAL_NUM; trial++){
  //         dycuckoo_uint32_experiment(
  //             (size_t)table_size,
  //             data.getInsertKeys(), data.getInsertVals(), data.getInsertLen(), data.getDatasetName(),
  //             data.getLookupKeys(), data.getLookupLen(), data.getWorkloadType(),
  //             fmt::format("trial: {}", trial),
  //             expmode
  //         );
  //     }
  // }

  // if (comp == COMP_WARPCORE) {
  //     for (int trial = 1; trial <= TRIAL_NUM; trial++){
  //         warpcore_uint32_experiment(
  //             (size_t)table_size,
  //             data.getInsertKeys(), data.getInsertVals(), data.getInsertLen(), data.getDatasetName(),
  //             data.getLookupKeys(), data.getLookupLen(), data.getWorkloadType(),
  //             fmt::format("trial: {}", trial),
  //             expmode
  //         );
  //     }
  // }

  if (comp == COMP_GPH) {
    for (int trial = 1; trial <= TRIAL_NUM; trial++) {
      geph_uint32_experiment((size_t)table_size, data.getInsertKeys(),
                             data.getInsertVals(), data.getInsertLen(),
                             data.getDatasetName(), data.getLookupKeys(),
                             data.getLookupLen(), data.getWorkloadType(),
                             fmt::format("trial: {}", trial), expmode);
    }
  }
}
#define DATASET_REDDIT "reddit"
#define DATASET_LINEITEM "lineitem"
#define DATASET_RANDOM "random"
#define DATASET_TAO "tao"
void AUTO_COMP() {
  int AUTO_COMP_comp = COMP_GPH;
  size_t AUTO_COMP_table_bytes = (size_t)(4.0 * 1024 * 1024 * 1024);
  int AUTO_COMP_pos = 0;
  std::string AUTO_COMP_dataset_name = DATASET_RANDOM;
  run_exp_on_single_competitors_fix_table_size(
      AUTO_COMP_comp, AUTO_COMP_dataset_name, fmt::format("{}", AUTO_COMP_pos),
      AUTO_COMP_table_bytes, EXP_MODE_NO_CHECK);
}

#define GAO 1

int main() {
  // LOOKUPTH_TABLESIZE_COMP_DATASET();
  // LOOKUPTH_POSITIVE_COMP_DATASET();

  // NCU_LOOKUPTH_TABLESIZE_COMP();
  // NCU_LOOKUPTH_POSITIVE_COMP();
  // AUTO_GEPH();
#if GAO == 1
  AUTO_GEPH();
#elif GAO == 2
  AUTO_COMP();
#elif GAO == 3
  AUTO_GEPH_LF_TEST();
#endif
  printf("ALL done 3\n");
  return 0;
}