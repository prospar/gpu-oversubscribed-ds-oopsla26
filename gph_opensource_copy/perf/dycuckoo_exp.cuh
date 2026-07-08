#pragma once
#include "configor/json.hpp"
#include "Exp_batch_result_holder.cuh"
#include "experiments.cuh"
#include "data_layout.cuh"
#include "static_cuckoo.cuh"
#include <unordered_set>

#define FIND


namespace dycuckoo_exp
{


using data_t = DataLayout<>::data_t;
using key_t = DataLayout<>::key_t;
using value_t = DataLayout<>::value_t;
/**
    * @return 1: if insert fail, 0, if insert succeed 
*/
static size_t check(
    const uint32_t *keys_to_insert,
    const uint32_t *vals_to_insert,
    const size_t insert_n,
    const uint32_t *keys_to_find,
    const uint32_t *vals_to_check,
    const size_t find_n,
    json::value &exp_res_object
){
    size_t total_checked = 0;
    size_t correct_checked = 0;
    std::unordered_map<uint32_t, uint32_t> m;
    for (int i = 0; i < insert_n; i++) {
        m.insert({keys_to_insert[i], vals_to_insert[i]});
    }
    
    for (int i = 0; i < find_n; i++) {
        total_checked += 1;
        auto ground_truth = m.find(keys_to_find[i]);
        if ((ground_truth == m.end()) && (vals_to_check[i] == 0)) {
            correct_checked += 1;
            // fmt::print("key {}, want {}, and {}\n", keys_to_find[i], "not exist", vals_to_check[i]);
        } 
        else if ((ground_truth != m.end()) && (ground_truth->second == vals_to_check[i])) {
            correct_checked += 1;
            // fmt::print("key {}, want {}, and {}\n",  keys_to_find[i], ground_truth->second, vals_to_check[i]);
        } else {
            // if (ground_truth == m.end())
                // fmt::print("key {}, want {}, but {}\n", keys_to_find[i], "not exist", vals_to_check[i]);
            // else 
                // fmt::print("key {}, want {}, but {}\n", keys_to_find[i], ground_truth->second, vals_to_check[i]);
        }
    }

    exp_res_object["total_checked"] = fmt::format("{}", total_checked);
    exp_res_object["correct_checked"] = fmt::format("{}", correct_checked);
    return total_checked - correct_checked;
}

    

void dycuckoo_static_find(
     uint32_t *keys_to_insert,
     uint32_t *vals_to_insert,
     size_t insert_n,
     uint32_t *keys_to_find,
     size_t find_n,
     Competitor_meta competitor_meta,
     float load_factor,
    json::value &exp_res_object,
    Time_recorder &time_recorder,
     bool do_check)
{
     key_t *keys_h = keys_to_insert;
     key_t *find_keys_h = keys_to_find;
     value_t *values_h = vals_to_insert;
     value_t *check_h = new value_t[find_n];
    
    vclog(INFO,"=== Dycuckoo bucket_size {} cg_size {} load factor {} ...", competitor_meta.bucket_size, competitor_meta.cooperative_group_size, load_factor);
    
    StaticCuckoo<512, 512> static_cuckoo(insert_n / load_factor);

    vclog(INFO, "construct Dycuckoo...");
    static_cuckoo.hash_insert(keys_h, values_h, insert_n);

    vclog(INFO, "lookup Dycuckoo...");
    static_cuckoo.hash_search(find_keys_h, check_h, find_n);
    
    vclog(INFO, "lookup Dycuckoo complete");
    if (do_check) {
        vclog(INFO, "check dycuckoo...");
        check(keys_to_insert, vals_to_insert, insert_n, keys_to_find, check_h, find_n, exp_res_object);
    }
    vclog(INFO, "finish Dycuckoo");
    // exp_res_object["pure_gpu_throughput"] = fmt::format("{} MOPS", (n * 1.0) / ((double)(time_used * MILLION)));
    
    exp_res_object["bucket_size"] = competitor_meta.bucket_size;
    exp_res_object["cooperative_group_size"] = competitor_meta.cooperative_group_size;

    delete[] check_h;
}



// need modification
void dycuckoo_sblf(
     uint32_t *keys_to_insert,
     uint32_t *vals_to_insert,
     size_t insert_n,
     Competitor_meta competitor_meta,
     float load_factor,
    json::value &exp_res_object,
    Time_recorder &time_recorder
)
{
    value_t *check_h = new value_t[insert_n];

    vclog(INFO,"=== Dycuckoo bucket_size {} cg_size {} load factor {} ...", competitor_meta.bucket_size, competitor_meta.cooperative_group_size, load_factor);
    if (competitor_meta.bucket_size == 16)
    {

        int error_maximum_ratio = (int)(SBLF_TEST_MAX_ABANDON_RATIO * insert_n); 
        
         key_t* pos = keys_to_insert;
        int step = insert_n / 100;
        while (true) {
            if (pos >= (keys_to_insert  + insert_n)) break;
            key_t* end_pos = std::min(pos+step, keys_to_insert+insert_n);
            vclog(INFO, "=== Insert batch containing {} KVs, already inserted {} KVs", step, pos-keys_to_insert);
            StaticCuckoo<512, 512> static_cuckoo(insert_n / load_factor);
            int realN = end_pos-keys_to_insert;
            static_cuckoo.hash_insert(keys_to_insert, vals_to_insert, realN);
            static_cuckoo.hash_search(keys_to_insert, check_h, realN);
            int error_cnt =  check(
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
                int final_error_cnt = error_cnt;
                vclog(INFO, "+===============dycuckoo sblf: {}\n", (realN - final_error_cnt) * 1.0 / insert_n);
                exp_res_object["effective_load_factor"] = (realN - final_error_cnt) * 1.0 / insert_n;
                break;
            }
            pos += step;
        }
    }
    else
    {
        panic("====================== error bucket size !!!!======================\n");
    }
    exp_res_object["bucket_size"] = competitor_meta.bucket_size;
    exp_res_object["cooperative_group_size"] = competitor_meta.cooperative_group_size;
    // delete []keys_h; need to remove otherwise double free
    delete[] check_h;
}

};