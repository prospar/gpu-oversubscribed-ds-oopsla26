#pragma once
#include <map>
#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <cstdint>
#include "log.h"

typedef enum Data_source_type_e {RANDOM, SERIAL, ZIPF, SINGLE_FILE, EXISTING_DATA_BASED} Data_source_type;

inline const char* Data_source_typeToString(Data_source_type e)
{
    switch (e)
    {
        case RANDOM: return "RANDOM";
        case SERIAL: return "SERIAL";
        case ZIPF: return "ZIPF";
        case SINGLE_FILE: return "SINGLE_FILE";
        case EXISTING_DATA_BASED: return "EXISTING_DATA_BASED";
        default: panic("Unsupported data source type"); return "";
    }
}

typedef struct Data_source_meta_s
{
    Data_source_type data_source_type;
    
    // EXISTING_DATA_BASED parameter
    double positive_rate;
    double load_factor;
    uint32_t* based_array; // input value to be insert.
    int based_array_n;

    std::string file_path;
} Data_source_meta;

void gen_random_unique_input(uint32_t * const vals, const int n);
void gen_single_file_uint32_input(std::string file_path, uint32_t * const vals, const int n);
void gen_find_input(Data_source_meta meta, uint32_t * const find, const int n, bool shuffle_enable=true);