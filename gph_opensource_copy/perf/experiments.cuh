#pragma once

#include "./../datasource/data_source.h"
#include <vector>
#include <string>
#include "./../common/include/log.h"

// 0.0001 means 0.01% data can be abandoned
#define SBLF_TEST_MAX_ABANDON_RATIO 0.0001

typedef enum Competitors_type_e {
    CUDPPIMPL_SHARED,
    CUDPPIMPL_NAIVE,
    SLAB_LIST,
    DYCUCKOO,
    CUDA_GPHOS,
    WARPCORE,
    GEPH
} Competitors_type;

inline const char* Competitors_typeToString(Competitors_type e)
{
    switch (e)
    {
        case CUDPPIMPL_SHARED: return "CUDPPIMPL_SHARED";
        case CUDPPIMPL_NAIVE: return "CUDPPIMPL_NAIVE";
        case SLAB_LIST: return "SLAB_LIST";
        case DYCUCKOO: return "DYCUCKOO";
        case CUDA_GPHOS: return "CUDA_GPHOS";
        case WARPCORE: return "WARPCORE";
        case GEPH: return "GEPH";
        default: panic("Unsupported competitor type"); return "";
    }
}

typedef struct Competitor_meta_s {
    Competitors_type competitor_type;
    double load_factor; // default 0.5

    // for Dycuckoo
    int bucket_size; // # items each bucket at most can have
    int cooperative_group_size;
    uint32_t bucket_num; // number of bucket

    // for CUDPPIMPL
    double evict_bound_factor; // evict_number = evict_bound_factor * ceil(log2((double)n)), default 4
    int num_of_funcs; // default 3 
    float space_usage; // for CUDPP

} Competitor_meta;

inline Competitor_meta create_dycuckoo_competitor(int bucket_size, int cg_size) {
    printf("bsize %d cg %d\n", bucket_size, cg_size);
    Competitor_meta competitor_meta;
    competitor_meta.competitor_type = DYCUCKOO;
    competitor_meta.bucket_size = bucket_size;
    competitor_meta.cooperative_group_size = cg_size;
    return competitor_meta;
}

inline Competitor_meta create_warpcore_competitor() {
    Competitor_meta competitor_meta;
    competitor_meta.competitor_type = WARPCORE;
    return competitor_meta;
}

inline Competitor_meta create_geph_competitor() {
    Competitor_meta competitor_meta;
    competitor_meta.competitor_type = GEPH;
    return competitor_meta;
}


inline Competitor_meta create_cudppimpl_competitor(bool use_shared_memory = false, int num_of_funcs = 4) // float space_usage = 2.33f) 
{
    Competitor_meta competitor_meta;
    competitor_meta.competitor_type = CUDPPIMPL_NAIVE;
    competitor_meta.num_of_funcs = num_of_funcs;
    return competitor_meta;
}


typedef enum Incremental_type_e {DOUBLED, CONSTANT, SINGLE} Incremental_type;
typedef struct Experiments_config_s {
    int trial_num;
    int64_t data_min_amount;
    int64_t data_max_amount;
    Incremental_type incremental_type;
    int incremental_constant; // if incremental_type==CONSTANT
    
    std::vector<Competitor_meta> competitors;
    int subtrial_num;

    // find experiments parameter
    double positive_rate; 
    double find_number_over_data_ratio; // int find_n = ceil(experiments_config.find_number_over_data_ratio * insert_n);

} Experiments_config;

inline int64_t getInitialDataAmount(Experiments_config config) {
    return config.data_min_amount;
}

inline int64_t getNextDataAmount(Experiments_config config, int64_t cur_amount) {
    if (config.incremental_type == DOUBLED) return cur_amount * 2;
    else if (config.incremental_type == CONSTANT) return cur_amount + config.incremental_constant;
    else if (config.incremental_type == SINGLE) return 0xFFFFFFFFFFFFFFF;
    else {
        panic("Unsupported incremental type.");
    }
}