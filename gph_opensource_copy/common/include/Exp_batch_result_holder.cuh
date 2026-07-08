#pragma once
#include <vector>
#include <string>
#include "./../../ThirdParties/configor/include/configor/json.hpp"
#include <chrono>
#include <ctime>
#include <map>
#include <fmt/core.h>
#include <utility>

#include <ostream> // for TimerHelp
#include <iostream> // for TimerHelp
using namespace configor;

class TimerHelp{
public:

    TimerHelp()
        : TimerHelp(0, "anonymous timer", std::cout)
    {
        //default stream, current device
    }

    TimerHelp(const std::string& label)
        : TimerHelp(0, label, std::cout)
    {
        //default stream, current device
    }


    TimerHelp(cudaStream_t stream, const std::string& label)
        : TimerHelp(stream, label, std::cout)
    {
        //user-defined stream, current device
    }

    TimerHelp(cudaStream_t stream, const std::string& label, std::ostream& outputstream)
        : calculatedDelta(true), elapsedTime(0), os(outputstream)
    {
        //user-defined stream, current device

        int curGpu = 0;
        cudaGetDevice(&curGpu);

        init(stream, label, curGpu);
        start();
    }

    TimerHelp(cudaStream_t stream, const std::string& label, int deviceId)
        : TimerHelp(stream, label, deviceId, std::cout)
    {
        //user-defined stream, user-defined device
    }

    TimerHelp(cudaStream_t stream, const std::string& label, int deviceId, std::ostream& outputstream)
        : calculatedDelta(true), elapsedTime(0), os(outputstream)
    {
        //user-defined stream, user-defined device

        init(stream, label, deviceId);
        start();
    }

    ~TimerHelp(){
        if(ongoing){
            stop();
        }

        int curGpu = 0;
        cudaGetDevice(&curGpu);
        cudaSetDevice(gpu);

        cudaEventDestroy(begin);
        cudaEventDestroy(end);

        cudaSetDevice(curGpu);
    }

    void start(){
        if(!calculatedDelta){
            float delta = 0.0f;
            cudaEventSynchronize(end);
            cudaEventElapsedTime(&delta, begin, end);
            elapsedTime += delta;
            calculatedDelta = true;
        }

        ongoing = true;

        int curGpu = 0;
        cudaGetDevice(&curGpu);
        cudaSetDevice(gpu);

        cudaEventRecord(begin, timedstream);

        cudaSetDevice(curGpu);
    }

    void stop(){
        int curGpu = 0;
        cudaGetDevice(&curGpu);
        cudaSetDevice(gpu);

        cudaEventRecord(end, timedstream);
        ongoing = false;
        calculatedDelta = false;

        cudaSetDevice(curGpu);
    }

    void reset(){
        ongoing = false;
        calculatedDelta = true;
        elapsedTime = 0;
    }

    float elapsed(){
        if(ongoing){
            stop();
        }

        if(!calculatedDelta){
            float delta = 0.0f;
            cudaEventSynchronize(end);
            cudaEventElapsedTime(&delta, begin, end);
            elapsedTime += delta;
            calculatedDelta = true;
        }

        return elapsedTime;
    }

    void print(){
        os << "TIMING: " << elapsed() << " ms (" << name << ")\n";
    }

    void print_throughput(std::size_t bytes, int num){
        const float delta = elapsed();

        const double gb = ((bytes)*(num))/1073741824.0;
        const double throughput = gb/((delta)/1000.0);
        const double ops = (num)/((delta)/1000.0);

        os << "THROUGHPUT: " << delta << " ms @ " << gb << " GB "
            << "-> " << ops << " elements/s or " <<
            throughput << " GB/s (" << name << ")\n";
    }

private:

    void init(cudaStream_t stream, const std::string& label, int deviceId){
        gpu = deviceId;
        timedstream = stream;
        name = label;

        int curGpu = 0;
        cudaGetDevice(&curGpu);
        cudaSetDevice(gpu);

        cudaEventCreate(&begin);
        cudaEventCreate(&end);

        cudaSetDevice(curGpu);
    }


    bool ongoing;
    bool calculatedDelta;
    int gpu;
    float elapsedTime;
    cudaStream_t timedstream;
    cudaEvent_t begin;
    cudaEvent_t end;
    std::ostream& os;
    std::string name;
};


class Exp_batch_result_holder {
    private:
        json::value exp_res;
        json::value batch_res_array;
        std::chrono::time_point<std::chrono::high_resolution_clock> ts;
    public:
        void initialize(const std::string batch_exp_id, const std::string batch_exp_type);
        json::value start_new_exp();
        void finish_cur_exp(json::value& exp_json_value);
        std::string finish_exp_batch(); 
};

class Timer_recorder_elem {
    public: 
        json::value* target_object;
        std::string key_for_timer;
        std::chrono::time_point<std::chrono::high_resolution_clock> ts;
        int64_t time_eps;
};

class Time_recorder {
    private:
        std::map<int, Timer_recorder_elem> records;
        int current_cnt;
    public:
        int register_timer(json::value& exp_json_value, const std::string key_for_timer);
        void register_timer(json::value& exp_json_value, const std::string key_for_timer, int handler_id);
        void pause_timer(int handler_id);
        void continue_timer(int handler_id);
        void finish_timer_and_record_us(int handler_id);
        void reset();
};




class UnifiedTimeRecorder {
    private:
        std::map<std::string, int64_t> records;
        std::map<std::string, bool> isGPUTable;
        std::map<std::string, std::pair<cudaEvent_t, cudaEvent_t>> gpu_timer;
        std::map<std::string, std::chrono::time_point<std::chrono::high_resolution_clock>> cpu_timer;
    public:
        void start_timer(const std::string entry_name, bool isGPU=true);
        void finish_timer(const std::string entry_name);
        void restart_timer(const std::string entry_name);
        json::value export_json_timer_results();
        std::map<std::string, int64_t> export_map_timer_results();
        void reset();
        int64_t get_timer_result(const std::string entry_name);
};

// void Exp_batch_result_holder::timer_start() {
//     ts = std::chrono::high_resolution_clock::now();
// }

// json::value Exp_batch_result_holder::timer_stop_and_record_us(json::value& exp_json_value, const std::string key_for_timer) {
//     auto te = std::chrono::high_resolution_clock::now();
//     exp_json_value[fmt::format("{}", key_for_timer)] = std::chrono::duration_cast<std::chrono::microseconds>(te - ts).count();
//     return exp_json_value;
// }
