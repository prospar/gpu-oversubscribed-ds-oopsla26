#pragma once
#include <iostream>
#include <warpcore/single_value_hash_table.cuh>
#include <helpers/timers.cuh>
#include <unordered_set>

#include "configor/json.hpp"
#include "Exp_batch_result_holder.cuh"
#include "experiments.cuh"

namespace warpcore_exp
{
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
    
    void build_and_search(
        uint32_t *keys_to_insert,
        uint32_t *vals_to_insert,
        size_t insert_n,
        uint32_t *keys_to_find,
        size_t find_n,
        warpcore::SingleValueHashTable<uint32_t, uint32_t> hash_table,
        uint32_t *check_h
    ) {
        using key_t = uint32_t;
        using value_t = uint32_t;
        using namespace warpcore;
        using hash_table_t = SingleValueHashTable<key_t, value_t>;

        key_t   *insert_keys_d;
        value_t *insert_values_d;
        cudaMalloc(&insert_keys_d,      sizeof(key_t)   *insert_n);
        cudaMalloc(&insert_values_d,    sizeof(value_t) *insert_n);
        
        cudaMemcpy(insert_keys_d,   keys_to_insert,   sizeof(key_t)     *insert_n,      cudaMemcpyHostToDevice);
        cudaMemcpy(insert_values_d, vals_to_insert, sizeof(value_t)   *insert_n,      cudaMemcpyHostToDevice);
        
        {
            TimerHelp timer("WarpCore insert");
            hash_table.insert(insert_keys_d, insert_values_d, (uint64_t) insert_n);    
            timer.print();
        }
        
        cudaDeviceSynchronize();
        
        key_t   *find_keys_d;
        value_t *result_d;
        cudaMalloc(&find_keys_d,      sizeof(key_t)   *find_n);
        cudaMalloc(&result_d,         sizeof(value_t) *find_n);
        
        cudaMemcpy(find_keys_d,     keys_to_find,       sizeof(key_t)     *find_n,      cudaMemcpyHostToDevice);
        cudaMemcpy(result_d,        check_h,    sizeof(value_t)   *find_n,      cudaMemcpyHostToDevice);
        
        {
            TimerHelp timer("WarpCore search");
            hash_table.retrieve(find_keys_d, (uint64_t) find_n, result_d);
            timer.print();
        }
        
        cudaMemcpy(check_h,         result_d,   sizeof(value_t)   *find_n,      cudaMemcpyDeviceToHost);
        
        
        if (insert_keys_d)   cudaFree(insert_keys_d);
        if (insert_values_d) cudaFree(insert_values_d);
        if (find_keys_d)     cudaFree(find_keys_d);
        if (result_d)        cudaFree(result_d);
    }

    void warpcore_find(
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
        using key_t = uint32_t;
        using value_t = uint32_t;
        using namespace warpcore;
        using hash_table_t = SingleValueHashTable<key_t, value_t>;
        value_t *check_h  = new value_t[find_n];
        
        int64_t capacity = insert_n / load_factor;
        hash_table_t hash_table(capacity);
        
        vclog(INFO, "=== warpcore load factor {} ...", load_factor);
        
        build_and_search(
            keys_to_insert,
            vals_to_insert,
            insert_n,
            keys_to_find,
            find_n,
            hash_table,
            check_h
        );

        if (do_check)
            check(keys_to_insert, vals_to_insert, insert_n, keys_to_find, check_h, find_n, exp_res_object);

        if (check_h)  delete[] check_h;
    }
}