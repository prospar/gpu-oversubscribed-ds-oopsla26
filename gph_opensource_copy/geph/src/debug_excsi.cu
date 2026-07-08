#include <iostream>
#include <string>
#include <vector>
#include <utility>
#include "GPHOS.cuh"
#include <algorithm>
#include "halfType.cuh"
#include "Exp_batch_result_holder.cuh"


int main() {
    const int cell_length = 48*1024*80;
    const int bucket_cap = 16;
    const int lookup_group_size = 16;
    const int bucket_n = 40;
    const int virtual_bucket_n = 8;
    GPHOSGPUTable<uint64_t, bucket_cap, lookup_group_size, 8, virtual_bucket_n> hash_table(
        cell_length,    
        bucket_n,
        114515);
        
    size_t keys_n = 200000000;
    uint32_t * keys = new uint32_t[keys_n];
    std::vector<std::pair<uint32_t, uint32_t>> res_kvs;
    for (uint32_t i = 0 ; i < keys_n; i++) {
        keys[i] = i+1;
    }
    
    UnifiedTimeRecorder recorder;
    hash_table.lookup_key_return_value_EXCSI(keys, keys_n, res_kvs, &recorder);

    fmt::print("adjust_throughput {} MOPS\nTIMING: {} ms (geph preprocess)\n\n",
    (keys_n)/recorder.get_timer_result("preprocess"), recorder.get_timer_result("preprocess") / 1000.00 );
    return 0;
}