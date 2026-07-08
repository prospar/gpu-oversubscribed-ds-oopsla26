#include <map>
#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <chrono>
#include <ctime>
#include <iostream>
#include <string>
#include <fmt/core.h>
#include "data_source.h"
#include "experiments.cuh"
#include <vector>

// 百分制
static Data_source_meta get_dummy_data_source_meta(int positive_ratio, int load_factor) {
    double pr = (1.0 * positive_ratio) / (1.0 * 100);
    double lf = (1.0 * load_factor) / (1.0 * 100);
    return Data_source_meta{RANDOM, pr, lf};
}

static Data_source_meta get_lineitem_source_meta(int positive_ratio, int load_factor) {
    double pr = (1.0 * positive_ratio) / (1.0 * 100);
    double lf = (1.0 * load_factor) / (1.0 * 100);
    Data_source_meta res{SINGLE_FILE, pr, lf};
    res.file_path = "datasource/lineitem.txt";
    return res;
}

static Data_source_meta get_reddit_source_meta(int positive_ratio, int load_factor) {
    double pr = (1.0 * positive_ratio) / (1.0 * 100);
    double lf = (1.0 * load_factor) / (1.0 * 100);
    Data_source_meta res{SINGLE_FILE, pr, lf};
    res.file_path = "datasource/reddit_author_uid_uint32.txt";
    return res;
}
static std::vector<Competitor_meta> get_dummy_competitor_list() {
    std::vector<Competitor_meta> res;
    
    // res.push_back(create_cudppimpl_competitor());
    // res.push_back(create_dycuckoo_competitor(16, 16)); // res.push_back(create_dycuckoo_competitor(bucket_num, 8, 8));
    // res.push_back(create_warpcore_competitor());
    res.push_back(create_geph_competitor());
    return res;
}

static std::vector<Competitor_meta> get_sblf_competitor_list() {
    std::vector<Competitor_meta> res;

    res.push_back(create_cudppimpl_competitor());
    // res.push_back(create_dycuckoo_competitor(16, 16)); 
    return res;
}

static Experiments_config get_dummy_experiment_config(int64_t n, int subtrial) {
    return Experiments_config {
        1,                     // trial number (how many times each experiment is conducted)          
        n,                     // least input size - 8
        n,                     // most input size - 15
        DOUBLED,               // how data size increase from least to most
        -1,                     
        get_dummy_competitor_list(), 
        subtrial,              // subtrial number - 3
        1.0,                   // 目前实验没用到这个, 用到的是Data_source_meta里面的positive rate
        1.0                    
    };
}

static Experiments_config get_sblf_exp_config(int64_t n, int subtrial) {
    return Experiments_config {
        1,                     // trial number (how many times each experiment is conducted)          
        n,                     // least input size - 8
        n,                     // most input size - 15
        DOUBLED,               // how data size increase from least to most
        -1,                     
        get_sblf_competitor_list(), 
        subtrial,              // subtrial number - 3
        1.0,                   // 目前实验没用到这个, 用到的是Data_source_meta里面的positive rate
        1.0                    
    };
}
/* 
    Usage: perf -n input_size -t subtrial -d run_cudpp [-b bucket_num] [-m min_n] [-a max_n] [-p positive_ratio] [-l load factor]
    -d run_cudpp: 0: dont run, 1: run
*/
int main(int argc, char *argv[])
{
    int o;
    int subtrial = 1;
    int run_cudpp; // useless
    uint32_t bucket_num; // useless
    int min_n, max_n;
    int pr = 0; // positive ratio
    int load = 50; // load factor
    while ( (o = getopt(argc, argv, "n:t:d:b:m:a:p:l:")) != -1) 
    {
        switch (o)
        {
        case 't':
            subtrial = atoi(optarg);
            break;
        case 'd':
            run_cudpp = atoi(optarg); 
            break;
        case 'b':
            bucket_num = std::stoul(optarg);
            break;
        case 'm':
            min_n = atoi(optarg);
            break;
        case 'a':
            max_n = atoi(optarg);
            break;
        case 'p':
            pr = atoi(optarg);
            break;
        case 'l':
            load = atoi(optarg);
            break;
        default:
            break;
        }
    }

    // pr = 100;
    // load = 100;
    // printf("sblf: positive ratio %d load factor %d\n ", pr, load);
    // conduct_small_batches_load_factor_test(
    //     get_dummy_data_source_meta(pr, load), // 配置 positive ratio 
    //     get_sblf_exp_config(67000000, subtrial), // 配置 competitors
    //     "sblf"
    // );

    pr = 0;
    load = 60;
    conduct_find_exp_batch(
        get_dummy_data_source_meta(pr, load), // 配置 positive ratio 
        get_dummy_experiment_config(120000000, subtrial), // 配置 competitors
        "random_find"
    );

    // // varying load factor step by step 
    // pr = 0;
    // load = 40;
    // while (load <= 100) {
    //     printf("change load factor: positive ratio %d load factor %d\n", pr, load);
    //     conduct_find_exp_batch(
    //         get_dummy_data_source_meta(pr, load), // 配置 positive ratio 
    //         get_dummy_experiment_config(120000000, subtrial), // 配置 competitors
    //         "random_find"
    //     );
    //     load += 10;
    //     printf("\n\n\n");
    // }

    // // varying positive ratio step by step
    // pr = 0;
    // load = 80;
    // while (pr <= 100) {
    //     printf("change pr: positive ratio %d load factor %d\n", pr, load);
    //     conduct_find_exp_batch(
    //         get_dummy_data_source_meta(pr, load), // 配置 positive ratio 
    //         get_dummy_experiment_config(120000000, subtrial), // 配置 competitors
    //         "random_find"
    //     );
    //     pr += 10;
    //     printf("\n\n\n");
    // }


    // conduct_find_exp_batch(
    //     get_lineitem_source_meta(pr, load), // 配置 positive ratio 
    //     get_dummy_experiment_config(29990000, subtrial), // 配置 competitors
    //     "lineitem_find"
    // );

    // conduct_find_exp_batch(
    //     get_reddit_source_meta(pr, load), // 配置 positive ratio 
    //     get_dummy_experiment_config(27250000, subtrial), // 配置 competitors
    //     "reddit_find"
    // );
}