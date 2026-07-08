#include <map>
#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <chrono>
#include <ctime>
#include <fmt/core.h>
#include "data_source.h"
#include "experiments.cuh"
#include <vector>
#include <string>
#include "configor/json.hpp"
#include "Exp_batch_result_holder.cuh"

#include "cudppimpl_naive_exp.cuh"
#include "dycuckoo_exp.cuh"
#include "warpcore_exp.cuh"
#include "geph_exp.cuh"

using namespace configor;
namespace de = dycuckoo_exp;
namespace wp = warpcore_exp;
namespace gh = geph_exp;

// #define FOUR_EXP // dycuckoo 4B exp

#ifdef FOUR_EXP

void conduct_dycuckoo_4B_exp_batch(Data_source_meta data_source_meta, Experiments_config experiments_config, std::string exp_id) {
    Exp_batch_result_holder batch_res_holder;
    Time_recorder timer_recorder;
    batch_res_holder.initialize(exp_id, "find");
    Data_source_type entrance_type = data_source_meta.data_source_type;
    
    // loop of trial
    for (int trial = 1; trial <= experiments_config.trial_num; trial++)
    {
        // loop of data amount
        for (int64_t insert_n = getInitialDataAmount(experiments_config); insert_n <= experiments_config.data_max_amount; insert_n = getNextDataAmount(experiments_config, insert_n))
        {
            vclog(INFO, "===Generating data ({}), size:{}.....", Data_source_typeToString(data_source_meta.data_source_type), insert_n);
            data_source_meta.data_source_type = entrance_type; // Bug fix: need to reset the data_source_type back to function entrance state
            vclog(INFO, "===Generating data complete ({}), size:{}", Data_source_typeToString(data_source_meta.data_source_type), insert_n);
            
            // loop of competitors
            for (Competitor_meta competitor_meta : experiments_config.competitors)
            {
                Competitors_type competitor = competitor_meta.competitor_type;
                for (int subtrial = 1; subtrial <= experiments_config.subtrial_num; subtrial++)
                {
                    json::value exp_res_object = batch_res_holder.start_new_exp();
                    exp_res_object["competitor"] = Competitors_typeToString(competitor);
                    exp_res_object["trial"] = trial;
                    exp_res_object["subtrial"] = subtrial;
                    exp_res_object["insert_size"] = insert_n;
                    exp_res_object["data_source_type"] = Data_source_typeToString(data_source_meta.data_source_type);
                    
                    cudaDeviceReset();
                    de::dycuckoo_4B_find(insert_n,competitor_meta);
                    
                    batch_res_holder.finish_cur_exp(exp_res_object);
                    timer_recorder.reset();
                }
            }
        }
    }
    fmt::print("{}\n", batch_res_holder.finish_exp_batch());
}

#else
void conduct_find_exp_batch(Data_source_meta data_source_meta, Experiments_config experiments_config, std::string exp_id)
{
    Exp_batch_result_holder batch_res_holder;
    Time_recorder timer_recorder;
    
    batch_res_holder.initialize(exp_id, "find");
    Data_source_type entrance_type = data_source_meta.data_source_type;
    // loop of trial
    for (int trial = 1; trial <= experiments_config.trial_num; trial++)
    {
        // loop of data amount
        for (int64_t n = getInitialDataAmount(experiments_config); n <= experiments_config.data_max_amount; n = getNextDataAmount(experiments_config, n))
        {
            uint32_t pool_size = n + n * (1.0 - data_source_meta.positive_rate) + 10;
            uint32_t *pool = new uint32_t[pool_size];
            uint32_t *vals_to_insert = new uint32_t[n];
            uint32_t *vals_to_find = new uint32_t[n];
            
            data_source_meta.data_source_type = entrance_type; // Bug fix: need to reset the data_source_type back to function entrance state
            vclog(INFO, "===Generating pool input ({}), pool size:{}.....", Data_source_typeToString(data_source_meta.data_source_type), pool_size);
            if (data_source_meta.data_source_type == RANDOM) 
                gen_random_unique_input(pool, pool_size);
            else if (data_source_meta.data_source_type == SINGLE_FILE) {
                vclog(INFO, "===File from {}",  data_source_meta.file_path);
                gen_single_file_uint32_input(data_source_meta.file_path, pool, pool_size);
            }
            else 
                panic("Unsupported data source type"); 

            vclog(INFO, "===Finish generating pool input======");
            for(int i = 0; i < 10; i++) {
                vclog(INFO, "Example data {}: {}", i, pool[i]);
            }
            
            vclog(INFO, "===Generating insert data ({}), insert size:{}.....", Data_source_typeToString(data_source_meta.data_source_type), n);
            memcpy(vals_to_insert, pool, sizeof(uint32_t) * n);
            vclog(INFO, "===Finish generating insert data======");
            
            data_source_meta.data_source_type = EXISTING_DATA_BASED;
            data_source_meta.based_array = pool;
            data_source_meta.based_array_n = pool_size;
            vclog(INFO, "===Generating find data ({}), find size:{}, positive ratio: {}.....", Data_source_typeToString(data_source_meta.data_source_type), n, data_source_meta.positive_rate);
            gen_find_input(data_source_meta, vals_to_find, n);
            vclog(INFO, "===Generating find data complete ({}), find size:{}", Data_source_typeToString(data_source_meta.data_source_type), n);
            
            // loop of competitors
            for (Competitor_meta competitor_meta : experiments_config.competitors)
            {
                Competitors_type competitor = competitor_meta.competitor_type;
                for (int subtrial = 1; subtrial <= experiments_config.subtrial_num; subtrial++)
                {
                    vclog(INFO, "===Experiment processing: competitor:{} trial:{} subtrial:{} insert_size:{}, find_size:{}", Competitors_typeToString(competitor), trial, subtrial, n, n);
                    json::value exp_res_object = batch_res_holder.start_new_exp();
                    exp_res_object["competitor"] = Competitors_typeToString(competitor);
                    exp_res_object["trial"] = trial;
                    exp_res_object["subtrial"] = subtrial;
                    exp_res_object["insert_size"] = n;
                    exp_res_object["find_size"] = n;
                    exp_res_object["load_factor"] = data_source_meta.load_factor;
                    exp_res_object["positive_ratio"] = data_source_meta.positive_rate;
                    exp_res_object["data_source_type"] = Data_source_typeToString(data_source_meta.data_source_type);
                    
                    cudaDeviceReset();
                    if (competitor == CUDPPIMPL_NAIVE)
                    {
                        cudppimpl_naive_find(vals_to_insert, 
                                            n, 
                                            vals_to_find, 
                                            n, 
                                            competitor_meta,
                                            data_source_meta, 
                                            exp_res_object, 
                                            timer_recorder);
                    }
                    else if (competitor == DYCUCKOO)
                    {
                        de::dycuckoo_static_find(vals_to_insert, 
                                                n, 
                                                vals_to_find, 
                                                n, 
                                                competitor_meta, 
                                                data_source_meta,
                                                exp_res_object, 
                                                timer_recorder);
                    }
                    else if (competitor == WARPCORE) {
                        wp::warpcore_find<uint32_t, uint32_t>(vals_to_insert,
                                          vals_to_find,
                                          n,
                                          competitor_meta,
                                          data_source_meta,
                                          exp_res_object,
                                          timer_recorder);
                    } 
                    else if (competitor == GEPH) {
                        gh::geph_find<uint32_t, uint32_t>(
                            vals_to_insert,
                            vals_to_find,
                            n,
                            competitor_meta,
                            data_source_meta,
                            exp_res_object,
                            timer_recorder
                        );
                    }
                    else
                    {
                        panic("Unsupported competitor type.");
                    }
                    cudaDeviceReset();
                    batch_res_holder.finish_cur_exp(exp_res_object);
                    timer_recorder.reset();
                }
            }
            if (pool) delete[] pool;
            if (vals_to_insert) delete[] vals_to_insert;
            if (vals_to_find) delete[] vals_to_find;
        }
    }
    fmt::print("{}\n", batch_res_holder.finish_exp_batch());
}

#endif

void conduct_small_batches_load_factor_test(Data_source_meta data_source_meta, Experiments_config experiments_config, std::string exp_id)
{
    Exp_batch_result_holder batch_res_holder;
    Time_recorder timer_recorder;
    
    batch_res_holder.initialize(exp_id, "sblf");
    Data_source_type entrance_type = data_source_meta.data_source_type;
    // loop of trial
    for (int trial = 1; trial <= experiments_config.trial_num; trial++)
    {
        // loop of data amount
        for (int64_t n = getInitialDataAmount(experiments_config); n <= experiments_config.data_max_amount; n = getNextDataAmount(experiments_config, n))
        {
            uint32_t pool_size = n + n * (1.0 - data_source_meta.positive_rate) + 10;
            uint32_t *pool = new uint32_t[pool_size];
            uint32_t *vals_to_insert = new uint32_t[n];
            uint32_t *vals_to_find = new uint32_t[n];
            
            data_source_meta.data_source_type = entrance_type; // Bug fix: need to reset the data_source_type back to function entrance state
            vclog(INFO, "===Generating pool input ({}), pool size:{}.....", Data_source_typeToString(data_source_meta.data_source_type), pool_size);
            if (data_source_meta.data_source_type == RANDOM) 
                gen_random_unique_input(pool, pool_size);
            else if (data_source_meta.data_source_type == SINGLE_FILE) {
                vclog(INFO, "===File from {}",  data_source_meta.file_path);
                gen_single_file_uint32_input(data_source_meta.file_path, pool, pool_size);
            }
            else 
                panic("Unsupported data source type"); 

            vclog(INFO, "===Finish generating pool input======");
            for(int i = 0; i < 10; i++) {
                vclog(INFO, "Example data {}: {}", i, pool[i]);
            }
            
            vclog(INFO, "===Generating insert data ({}), insert size:{}.....", Data_source_typeToString(data_source_meta.data_source_type), n);
            memcpy(vals_to_insert, pool, sizeof(uint32_t) * n);
            vclog(INFO, "===Finish generating insert data======");
            
            data_source_meta.data_source_type = EXISTING_DATA_BASED;
            data_source_meta.based_array = pool;
            data_source_meta.based_array_n = pool_size;
            vclog(INFO, "===Generating find data ({}), find size:{}, positive ratio: {}.....", Data_source_typeToString(data_source_meta.data_source_type), n, data_source_meta.positive_rate);
            gen_find_input(data_source_meta, vals_to_find, n, false);
            vclog(INFO, "===Generating find data complete ({}), find size:{}", Data_source_typeToString(data_source_meta.data_source_type), n);
            
            // loop of competitors
            for (Competitor_meta competitor_meta : experiments_config.competitors)
            {
                Competitors_type competitor = competitor_meta.competitor_type;
                for (int subtrial = 1; subtrial <= experiments_config.subtrial_num; subtrial++)
                {
                    vclog(INFO, "===Experiment processing: competitor:{} trial:{} subtrial:{} insert_size:{}, find_size:{}", Competitors_typeToString(competitor), trial, subtrial, n, n);
                    json::value exp_res_object = batch_res_holder.start_new_exp();
                    exp_res_object["competitor"] = Competitors_typeToString(competitor);
                    exp_res_object["trial"] = trial;
                    exp_res_object["subtrial"] = subtrial;
                    exp_res_object["insert_size"] = n;
                    exp_res_object["find_size"] = n;
                    exp_res_object["load_factor"] = data_source_meta.load_factor;
                    exp_res_object["positive_ratio"] = data_source_meta.positive_rate;
                    exp_res_object["data_source_type"] = Data_source_typeToString(data_source_meta.data_source_type);
                    
                    cudaDeviceReset();
                    if (competitor == CUDPPIMPL_NAIVE)
                    {
                        cudppimpl_naive_sblf(vals_to_insert, 
                            n, 
                            vals_to_find, 
                            n, 
                            competitor_meta,
                            data_source_meta, 
                            exp_res_object, 
                            timer_recorder);
                    }
                    else if (competitor == DYCUCKOO)
                    {
                        de::dycuckoo_sblf(vals_to_insert, 
                                                n, 
                                                vals_to_find, 
                                                n, 
                                                competitor_meta, 
                                                data_source_meta,
                                                exp_res_object, 
                                                timer_recorder);
                    }
                    else if (competitor == WARPCORE) {
                        panic("Unsupported competitor type.");
                    } 
                    else if (competitor == GEPH) {
                        panic("Unsupported competitor type.");
                    }
                    else
                    {
                        panic("Unsupported competitor type.");
                    }
                    cudaDeviceReset();
                    batch_res_holder.finish_cur_exp(exp_res_object);
                    timer_recorder.reset();
                }
            }
            if (pool) delete[] pool;
            if (vals_to_insert) delete[] vals_to_insert;
            if (vals_to_find) delete[] vals_to_find;
        }
    }
    fmt::print("{}\n", batch_res_holder.finish_exp_batch());
}



#ifdef LOAD_FACTOR

int conduct_load_factor_exp_batch(Data_source_meta data_source_meta, Experiments_config experiments_config, std::string exp_id)
{
    srand(time(NULL));
    Exp_batch_result_holder batch_res_holder;
    Time_recorder timer_recorder;
    batch_res_holder.initialize(exp_id, "load_factor test");
    bool insert_fail = false;
    // loop of trial
    for (int trial = 1; trial <= experiments_config.trial_num; trial++)
    {
        // loop of data amount
        for (int64_t n = getInitialDataAmount(experiments_config); n <= experiments_config.data_max_amount; n = getNextDataAmount(experiments_config, n))
        {
            uint32_t *vals_to_insert = new uint32_t[n];
            vclog(INFO, "===Generating data ({}), size:{}.....", Data_source_typeToString(data_source_meta.data_source_type), n);
            gen_input(data_source_meta, vals_to_insert, n);
            vclog(INFO, "===Generating data complete ({}), size:{}", Data_source_typeToString(data_source_meta.data_source_type), n);
            // loop of competitors
            for (Competitor_meta competitor_meta : experiments_config.competitors)
            {
                bool over_max_evict = false;
                Competitors_type competitor = competitor_meta.competitor_type;
                for (int subtrial = 1; subtrial <= experiments_config.subtrial_num; subtrial++)
                {
                    vclog(INFO, "===Experiment processing: competitor:{} trial:{} size:{}", Competitors_typeToString(competitor), trial, n);
                    json::value exp_res_object = batch_res_holder.start_new_exp();
                    exp_res_object["competitor"] = Competitors_typeToString(competitor);
                    exp_res_object["trial"] = trial;
                    exp_res_object["subtrial"] = subtrial;
                    exp_res_object["data_amount"] = n;
                    exp_res_object["data_source_type"] = Data_source_typeToString(data_source_meta.data_source_type);

                    cudaDeviceReset();
                    over_max_evict = over_max_evict | de::dycuckoo_LF_test(vals_to_insert, n, competitor_meta, exp_res_object, timer_recorder);
                    batch_res_holder.finish_cur_exp(exp_res_object);
                    timer_recorder.reset();
                }
                if (over_max_evict) insert_fail = true;
            }
            delete[] vals_to_insert;
        }
    }
    fmt::print("{}\n", batch_res_holder.finish_exp_batch());
    return insert_fail;
}

#endif