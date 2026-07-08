#include "Exp_batch_result_holder.cuh"
#include "log.h"

void Exp_batch_result_holder::initialize(const std::string batch_exp_id, const  std::string batch_exp_type){
    exp_res["exp_batch_meta"] = json::object{
        {"exp_batch_id", batch_exp_id},
        {"exp_batch_start_time", time(0)},
        {"exp_batch_type", batch_exp_type},
    };  
    batch_res_array = json::array{};
    batch_res_array.clear();
}
json::value Exp_batch_result_holder::start_new_exp(){
    json::value exp_res_object = json::object{};
    exp_res_object.clear();
    exp_res_object["exp_time"] = time(0);
    return exp_res_object;
}
void Exp_batch_result_holder::finish_cur_exp(json::value& exp_json_value){
    batch_res_array.push_back(exp_json_value);
}
std::string Exp_batch_result_holder::finish_exp_batch(){
    exp_res["exp_batch_res"] = batch_res_array;
    return json::dump(exp_res);
}

int Time_recorder::register_timer(json::value& exp_json_value, const std::string key_for_timer) {
    int handler_id = current_cnt++;

    Timer_recorder_elem elem;
    elem.target_object = &exp_json_value;
    elem.key_for_timer = key_for_timer;
    elem.ts = std::chrono::high_resolution_clock::now();
    elem.time_eps = 0;
    records[handler_id] = std::move(elem);

    return handler_id;
}

void Time_recorder::register_timer(json::value& exp_json_value, const std::string key_for_timer, int handler_id){
    if (records.count(handler_id) > 0) {
        continue_timer(handler_id);
        return;
    }
    Timer_recorder_elem elem;
    elem.target_object = &exp_json_value;
    elem.key_for_timer = key_for_timer;
    elem.ts = std::chrono::high_resolution_clock::now();
    elem.time_eps = 0;
    records[handler_id] = std::move(elem);
}

void Time_recorder::finish_timer_and_record_us(int handler_id) {
    auto te = std::chrono::high_resolution_clock::now();
    Timer_recorder_elem elem = std::move(records[handler_id]);
    
    auto res = std::chrono::duration_cast<std::chrono::microseconds>(te - elem.ts).count();
    elem.time_eps += res;
    (*elem.target_object)[fmt::format("{}", elem.key_for_timer)] = elem.time_eps;
}


void Time_recorder::pause_timer(int handler_id){
    auto te = std::chrono::high_resolution_clock::now();
    Timer_recorder_elem elem = records[handler_id];
    auto res = std::chrono::duration_cast<std::chrono::microseconds>(te - elem.ts).count();
    elem.time_eps += res;
    records[handler_id] = elem;
    (*elem.target_object)[fmt::format("{}", elem.key_for_timer)] = elem.time_eps;
} 

void Time_recorder::continue_timer(int handler_id){
    Timer_recorder_elem elem = records[handler_id];
    elem.ts = std::chrono::high_resolution_clock::now();
    records[handler_id] = elem;
}

void Time_recorder::reset() {
    records.clear();
}




void UnifiedTimeRecorder::start_timer(const std::string entry_name, bool isGPU) {
    if (isGPU) {
        cudaEvent_t sta, sto;
        gpu_timer[entry_name] = std::make_pair(sta, sto);
        auto &start = gpu_timer[entry_name].first;
        auto &stop = gpu_timer[entry_name].second;
        cudaEventCreate(&start);
        cudaEventCreate(&stop);

        cudaEventRecord(start, 0);

        records[entry_name] = 0;
        isGPUTable[entry_name] = isGPU;
    }
    else {
        auto start = std::chrono::high_resolution_clock::now();
        cpu_timer[entry_name] = start;
        records[entry_name] = 0;
        isGPUTable[entry_name] = isGPU;
    }
}

void UnifiedTimeRecorder::finish_timer(const std::string entry_name) {
    if (isGPUTable[entry_name]) {
        auto &start = gpu_timer[entry_name].first;
        auto &stop = gpu_timer[entry_name].second;
        cudaEventRecord(stop, 0);
        cudaEventSynchronize(stop);

        float time_ms;
        cudaEventElapsedTime( &time_ms, start, stop );
        records[entry_name] += (int64_t)(time_ms * 1000);

        cudaEventDestroy( start );
        cudaEventDestroy( stop );
    }
    else {
        auto start = cpu_timer[entry_name];
        auto stop = std::chrono::high_resolution_clock::now();
        auto res = std::chrono::duration_cast<std::chrono::microseconds>(stop - start).count();
        records[entry_name] += (int64_t)(res);
    }
}

void UnifiedTimeRecorder::restart_timer(const std::string entry_name) {
    if (isGPUTable[entry_name]) {
        cudaEvent_t sta, sto;
        gpu_timer[entry_name] = std::make_pair(sta, sto);
        auto &start = gpu_timer[entry_name].first;
        auto &stop = gpu_timer[entry_name].second;
        cudaEventCreate(&start);
        cudaEventCreate(&stop);

        cudaEventRecord(start, 0);
    }
    else {
        auto start = std::chrono::high_resolution_clock::now();
        cpu_timer[entry_name] = start;
    }
}

json::value UnifiedTimeRecorder::export_json_timer_results() {
    json::value json_object = json::object{};
    for (auto it = records.begin(); it != records.end(); ++it) {
        std::string key = it->first;
        int64_t value = it->second;
        json_object[key] = value;
    }
    return json_object;
}
    
std::map<std::string, int64_t> UnifiedTimeRecorder::export_map_timer_results() {
    return records;
}


void UnifiedTimeRecorder::reset() {
    records.clear();
    isGPUTable.clear();
    gpu_timer.clear();
    cpu_timer.clear();
}

int64_t UnifiedTimeRecorder::get_timer_result(const std::string entry_name) {
    return records[entry_name];
}
