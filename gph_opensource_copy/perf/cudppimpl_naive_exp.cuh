#pragma once
#include "common.h"
#include "configor/json.hpp"
#include "Exp_batch_result_holder.cuh"
#include "cuckoo-cuda-naive.cuh"
#include <unordered_map>

// return error count
static size_t check(
    const uint32_t *keys_to_insert,
    const uint32_t *vals_to_insert,
    const size_t insert_n,
    const uint32_t *keys_to_find,
    const uint32_t *vals_to_check,
    const size_t find_n,
    json::value &exp_res_object
) {
    size_t total_checked = 0;
    size_t correct_checked = 0;
    std::unordered_map<uint32_t, uint32_t> m;
    for (int i = 0; i < insert_n; i++) {
        m.insert({keys_to_insert[i], vals_to_insert[i]});
    }
    
    for (int i = 0; i < find_n; i++) {
        total_checked += 1;
        auto ground_truth = m.find(keys_to_find[i]);
        if ((ground_truth == m.end()) && (vals_to_check[i] == 0xffffffffu)) {
            correct_checked += 1;
            // fmt::print("key {}, want {}, and {}\n", keys_to_find[i], "not exist", vals_to_check[i]);
        } 
        else if ((ground_truth != m.end()) && (ground_truth->second == vals_to_check[i])) {
            correct_checked += 1;
            // fmt::print("key {}, want {}, and {}\n",  keys_to_find[i], ground_truth->second, vals_to_check[i]);
        } else {
            // if (ground_truth == m.end())
            //     fmt::print("key {}, want {}, but {}\n", keys_to_find[i], "not exist", vals_to_check[i]);
            // else 
            //     fmt::print("key {}, want {}, but {}\n", keys_to_find[i], ground_truth->second, vals_to_check[i]);
        }
    }

    exp_res_object["total_checked"] = fmt::format("{}", total_checked);
    exp_res_object["correct_checked"] = fmt::format("{}", correct_checked);
    return total_checked - correct_checked;
}

/*
 * Main entrance for the performance test.
 *
 * Prerequirests: we assume
 *   1. Value range do not cover EMPTY_CELL (i.e. 0).
 *   2. Value range do not exceed value-field width.
 *   3. No repeated keys inserted (so we skipped duplication check).
 *   4. Table size must be a multiple of BUCKET_SIZE.
 *   5. Only inserting into an empty table. No updating. (o.w. the rehashing part should be rewritten.)
 *
 * Currently supported types:
 *   uint[8, 16, 32]_t
 * */

void cudppimpl_naive_find(
    const uint32_t *keys_to_insert,
    const uint32_t *vals_to_insert,
    const size_t insert_n,
    const uint32_t *keys_to_find,
    const size_t find_n,
    const Competitor_meta competitor_meta,
    const float load_factor,
    json::value &exp_res_object,
    Time_recorder &time_recorder,
    const bool do_check
)
{
    uint32_t *check_h = new uint32_t[find_n];
    
    memset(check_h, 0, find_n * sizeof(uint32_t));
    
    float space_usage = (float) (1.0 / load_factor);
    
    vclog(INFO, "construct cudppimpl...");
    CuckooHashTableCuda_Naive<uint32_t> hash_table(insert_n, space_usage, competitor_meta.num_of_funcs);
    exp_res_object["attempts"] = fmt::format("Need {} attempts to build", hash_table.insert_vals(keys_to_insert, vals_to_insert, insert_n));
    vclog(INFO, "lookup cudppimpl...");
    
    hash_table.lookup_vals(keys_to_find, check_h, find_n);
    vclog(INFO, "lookup cudppimpl complete");
    if (do_check) {
        vclog(INFO, "check cudppimpl...");
        check(keys_to_insert, vals_to_insert, insert_n, keys_to_find, check_h, find_n, exp_res_object);
    }
    vclog(INFO, "finish cudppimpl");
    delete [] check_h;
}

void cudppimpl_naive_sblf(
    const uint32_t *keys_to_insert,
    const uint32_t *vals_to_insert,
    const size_t insert_n,
    const Competitor_meta competitor_meta,
    const float load_factor,
    json::value &exp_res_object,
    Time_recorder &time_recorder
)
{
    uint32_t *check_h = new uint32_t[insert_n];
    
    float space_usage = (float) (1.0 / load_factor);
    vclog(INFO, "=== CUDPP space usage {}", space_usage);
    size_t error_maximum_ratio = (size_t)(SBLF_TEST_MAX_ABANDON_RATIO * insert_n); 

    const uint32_t* pos = keys_to_insert;
    size_t step = insert_n / 100;
    while (true) {
        if (pos >= (keys_to_insert  + insert_n)) break;
        const uint32_t* end_pos = std::min(pos+step, keys_to_insert+insert_n);
        int realN = end_pos-keys_to_insert;
        vclog(INFO, "=== Insert batch containing {} KVs, already inserted {} KVs", step, pos-keys_to_insert);

        // bool success = hash_table.insert_vals(keys_h, vals_h, n);
        CuckooHashTableCuda_Naive<uint32_t> hash_table(insert_n, space_usage, competitor_meta.num_of_funcs);
        exp_res_object["attempts"] = fmt::format("Need {} attempts to build", hash_table.insert_vals(keys_to_insert, vals_to_insert, realN));
        
        hash_table.lookup_vals(keys_to_insert, check_h, realN);
        size_t error_cnt = check(
            keys_to_insert,
            vals_to_insert,
            realN,
            keys_to_insert,
            check_h,
            realN,
            exp_res_object
        );
        
        vclog(INFO, "=== current lf {}, check error cnt {}, error tolerance {}  ", (realN - error_cnt) * 1.0 / insert_n, error_cnt, error_maximum_ratio);
        if (error_cnt > error_maximum_ratio) {
            int final_err_cnt = error_cnt;
            vclog(INFO, "+===============cudpp sblf: {}\n",(realN - final_err_cnt) * 1.0 / insert_n);
            exp_res_object["effective_load_factor"] = (realN - final_err_cnt) * 1.0 / insert_n;
            break;
        }
        pos += step;
    }
    delete [] check_h;
}