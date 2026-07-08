
// void cudppimpl_uint32_experiment(
//     const size_t hash_table_size_bytes,
//     const uint32_t* dataset_key, const uint32_t* dataset_values,
//     const size_t dataset_len, const std::string dataset_name_for_record,
//     const uint32_t* workload, const size_t workload_len, const std::string workload_name_for_record,
//     const std::string extra_comment_message,
//     const int exp_mode
// ) {
//     Competitor_meta competitor_meta = create_cudppimpl_competitor();
//     float load_factor =  (sizeof(uint32_t) * 2 * dataset_len) * 1.0/ hash_table_size_bytes;
//     Time_recorder timer_recorder;

//     Exp_batch_result_holder batch_res_holder;
//     batch_res_holder.initialize("default_exp", "default");
//     json::value exp_res_object = batch_res_holder.start_new_exp();
//     exp_res_object["competitor"] = "cudppimpl";
//     exp_res_object["load_factor_upper_bound"] = load_factor;
//     exp_res_object["exp_mode"] = exp_mode;
//     exp_res_object["timestamp"] = getCurrentTimestamp();
//     exp_res_object["table_size"] = hash_table_size_bytes;
//     exp_res_object["dataset"] = dataset_name_for_record;
//     exp_res_object["dataset_len"] = dataset_len;
//     exp_res_object["workload"] = workload_name_for_record;
//     exp_res_object["workload_len"] = workload_len;
//     exp_res_object["comment"] = extra_comment_message;

//     // fmt::print("{}\n", json::dump(exp_res_object));

//     if (exp_mode == EXP_MODE_EFFECTIVE_LOAD_FACTOR_TEST) {
//         cudppimpl_naive_sblf(dataset_key, dataset_values, dataset_len,
//                competitor_meta,
//                load_factor,
//                exp_res_object,
//                timer_recorder
//            );
//     }
//     else if (exp_mode == EXP_MODE_CHECK || exp_mode == EXP_MODE_NO_CHECK) {
//         cudppimpl_naive_find(dataset_key, dataset_values, dataset_len,
//             workload, workload_len,
//                competitor_meta,
//                load_factor,
//                exp_res_object,
//                timer_recorder,
//                exp_mode == EXP_MODE_CHECK
//            );
//     } else {
//         printf("Unknown mode.");
//     }

//     batch_res_holder.finish_cur_exp(exp_res_object);
//     fmt::print("{}\n", batch_res_holder.finish_exp_batch());
// }

// void dycuckoo_uint32_experiment(
//      size_t hash_table_size_bytes,
//      uint32_t* dataset_key,  uint32_t* dataset_values,
//      size_t dataset_len,  std::string dataset_name_for_record,
//      uint32_t* workload,  size_t workload_len,  std::string workload_name_for_record,
//      std::string extra_comment_message,
//      int exp_mode
// ) {
//     Competitor_meta competitor_meta = create_dycuckoo_competitor(16, 16);
//     float load_factor =  (sizeof(uint32_t) * 2 * dataset_len) * 1.0/ hash_table_size_bytes;
//     Time_recorder timer_recorder;

//     Exp_batch_result_holder batch_res_holder;
//     batch_res_holder.initialize("default_exp", "default");
//     json::value exp_res_object = batch_res_holder.start_new_exp();
//     exp_res_object["competitor"] = "dycuckoo";
//     exp_res_object["load_factor_upper_bound"] = load_factor;
//     exp_res_object["exp_mode"] = exp_mode;
//     exp_res_object["timestamp"] = getCurrentTimestamp();
//     exp_res_object["table_size"] = hash_table_size_bytes;
//     exp_res_object["dataset"] = dataset_name_for_record;
//     exp_res_object["dataset_len"] = dataset_len;
//     exp_res_object["workload"] = workload_name_for_record;
//     exp_res_object["workload_len"] = workload_len;
//     exp_res_object["comment"] = extra_comment_message;

//     // fmt::print("{}\n", json::dump(exp_res_object));

//     if (exp_mode == EXP_MODE_EFFECTIVE_LOAD_FACTOR_TEST) {
//         dycuckoo_exp::dycuckoo_sblf(dataset_key, dataset_values, dataset_len,
//                competitor_meta,
//                load_factor,
//                exp_res_object,
//                timer_recorder
//            );
//     }
//     else if (exp_mode == EXP_MODE_CHECK || exp_mode == EXP_MODE_NO_CHECK) {
//         dycuckoo_exp::dycuckoo_static_find(dataset_key, dataset_values, dataset_len,
//             workload, workload_len,
//                competitor_meta,
//                load_factor,
//                exp_res_object,
//                timer_recorder,
//                exp_mode == EXP_MODE_CHECK
//            );
//     } else {
//         printf("Unknown mode.");
//     }

//     batch_res_holder.finish_cur_exp(exp_res_object);
//     fmt::print("{}\n", batch_res_holder.finish_exp_batch());
// }

// void warpcore_uint32_experiment(
//     size_t hash_table_size_bytes,
//     uint32_t* dataset_key,  uint32_t* dataset_values,
//     size_t dataset_len,  std::string dataset_name_for_record,
//     uint32_t* workload,  size_t workload_len,  std::string workload_name_for_record,
//     std::string extra_comment_message,
//     int exp_mode
// ) {
//    Competitor_meta competitor_meta = create_warpcore_competitor();
//    float load_factor =  (sizeof(uint32_t) * 2 * dataset_len) * 1.0/ hash_table_size_bytes;
//    Time_recorder timer_recorder;

//    Exp_batch_result_holder batch_res_holder;
//    batch_res_holder.initialize("default_exp", "default");
//    json::value exp_res_object = batch_res_holder.start_new_exp();
//    exp_res_object["competitor"] = "warpcore";
//    exp_res_object["load_factor_upper_bound"] = load_factor;
//    exp_res_object["exp_mode"] = exp_mode;
//    exp_res_object["timestamp"] = getCurrentTimestamp();
//    exp_res_object["table_size"] = hash_table_size_bytes;
//    exp_res_object["dataset"] = dataset_name_for_record;
//    exp_res_object["dataset_len"] = dataset_len;
//    exp_res_object["workload"] = workload_name_for_record;
//    exp_res_object["workload_len"] = workload_len;
//    exp_res_object["comment"] = extra_comment_message;

//    // fmt::print("{}\n", json::dump(exp_res_object));

//    if (exp_mode == EXP_MODE_EFFECTIVE_LOAD_FACTOR_TEST) {
//     //    warpcore_exp::warpcore_sblf(dataset_key, dataset_values, dataset_len,
//     //           competitor_meta,
//     //           load_factor,
//     //           exp_res_object,
//     //           timer_recorder
//     //       );
//     printf("Not implement");
//    }
//    else if (exp_mode == EXP_MODE_CHECK || exp_mode == EXP_MODE_NO_CHECK) {
//     warpcore_exp::warpcore_find(dataset_key, dataset_values, dataset_len,
//            workload, workload_len,
//               competitor_meta,
//               load_factor,
//               exp_res_object,
//               timer_recorder,
//               exp_mode == EXP_MODE_CHECK
//           );
//    } else {
//        printf("Unknown mode.");
//    }

//    batch_res_holder.finish_cur_exp(exp_res_object);
//    fmt::print("{}\n", batch_res_holder.finish_exp_batch());
// }

void geph_uint32_experiment(size_t hash_table_size_bytes, uint32_t *dataset_key,
                            uint32_t *dataset_values, size_t dataset_len,
                            std::string dataset_name_for_record,
                            uint32_t *workload, size_t workload_len,
                            std::string workload_name_for_record,
                            std::string extra_comment_message, int exp_mode) {
  Competitor_meta competitor_meta = create_geph_competitor();
  float load_factor =
      (sizeof(uint32_t) * 2 * dataset_len) * 1.0 / hash_table_size_bytes;
  Time_recorder timer_recorder;
  Exp_batch_result_holder batch_res_holder;
  batch_res_holder.initialize("default_exp", "default");
  json::value exp_res_object = batch_res_holder.start_new_exp();
  exp_res_object["competitor"] = "geph";
  exp_res_object["load_factor_upper_bound"] = load_factor;
  exp_res_object["exp_mode"] = exp_mode;
  exp_res_object["timestamp"] = getCurrentTimestamp();
  exp_res_object["table_size"] = hash_table_size_bytes;
  exp_res_object["dataset"] = dataset_name_for_record;
  exp_res_object["dataset_len"] = dataset_len;
  exp_res_object["workload"] = workload_name_for_record;
  exp_res_object["workload_len"] = workload_len;
  exp_res_object["comment"] = extra_comment_message;

  // fmt::print("{}\n", json::dump(exp_res_object));

  if (exp_mode == EXP_MODE_EFFECTIVE_LOAD_FACTOR_TEST) {
    geph_exp::geph_test_loadfactor(dataset_len, load_factor, exp_res_object,
                                   timer_recorder);
  } else if (exp_mode == EXP_MODE_CHECK || exp_mode == EXP_MODE_NO_CHECK) {
    geph_exp::geph_find(dataset_key, dataset_values, dataset_len, workload,
                        workload_len, competitor_meta, load_factor,
                        exp_res_object, timer_recorder,
                        exp_mode == EXP_MODE_CHECK);
  } else {
    printf("Unknown mode.");
  }

  batch_res_holder.finish_cur_exp(exp_res_object);
  fmt::print("{}\n", batch_res_holder.finish_exp_batch());
}