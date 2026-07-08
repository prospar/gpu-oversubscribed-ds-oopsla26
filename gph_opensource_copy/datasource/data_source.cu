#include <map>
#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <cstdint>
#include "log.h"
#include "data_source.h"
#include "mt19937ar.h"
#include "random_numbers.h"

#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <stdexcept>

#include <cstdio>
#include <string.h>             // memcpy
#include <limits>

#define PER

void gen_serial_input(uint32_t * vals, const int n) 
{
    int count = 0;
    while (count < n) {
        // vals[count] = (count + 1) * 997 - (genrand_int32() % 997);
        vals[count] = (count + 1);
        ++count;
    }
#ifdef PER
    for (int idx1 = 0; idx1 < n; idx1++) {
        int l = n - idx1;
        int idx2 = idx1 + (genrand_int32() % l);
        std::swap(vals[idx1], vals[idx2]);
    }
#endif
}

void gen_random_unique_input(uint32_t * const vals, const int n) {
    GetUniqueRandomNumbers(vals, n);
}

void gen_single_file_uint32_input(std::string file_path, uint32_t * const vals, const int n) {
    std::ifstream file(file_path);
    if (!file.is_open()) {
        throw std::runtime_error("Error opening file " + file_path);
    }

    std::vector<uint32_t> values;
    uint32_t value;
    int count = 0;

    while (file >> value) {
        values.push_back(value);
        count++;
        if (count >= n) {
            break;
        }
    }

    if (count < n) {
        throw std::runtime_error("Number of lines in file is less than n.");
    }

    for (int i = 0; i < n; i++) {
        vals[i] = values[i];
    }
}


static void help_shuffle(const int n,
                  uint32_t *random_number) {
  // Fisher-Yates shuffle the unique numbers.
  for (unsigned index_1 = 0; index_1 < n; ++index_1) {
    unsigned num_left = n - index_1;
    unsigned index_2  = index_1 + (genrand_int32() % num_left);
    uint32_t tmp = random_number[index_1];
    random_number[index_1] = random_number[index_2];
    random_number[index_2] = tmp;
  }
}

void gen_find_input(Data_source_meta meta, uint32_t * const find, const int n, bool shuffle_enable) {
    int positive_n = meta.positive_rate * n;
    int negative_n = n - positive_n;

    printf("n: %d\n",n);
    printf("positive n: %d\n", positive_n);
    printf("negative n: %d\n", negative_n);

    if (positive_n) {
        memcpy(find, meta.based_array, sizeof(uint32_t) * positive_n);
    }

    if (negative_n) {
        memcpy(find + positive_n, meta.based_array + n, sizeof(uint32_t) * negative_n);
    }
    if (shuffle_enable)
        help_shuffle(n, find);
}