// for external usage
#pragma once

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <ctime>
#include <vector>

#include "./../../common/include/Exp_batch_result_holder.cuh"
#include "./../../common/include/log.h"
#include "./../../geph/include/inner_header/GPHOS_config.cuh"

#include "./../../geph/include/halfType.cuh"

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size = 8, int virtual_bucket_n = 16>
class GPHOSGPUTable {
private:
  /** Experiment members. */
  json::value *exp_object = nullptr;
  Time_recorder *time_recorder = nullptr;

  int _cells_length;
  int _bucket_n;

  int _rand_seed;

  int _size;
  T *_data;       // memset 0xff for initialization,
  CELL_T *_cells; // first element for counter, the rest for cells.

  void validateSettings();

public:
  GPHOSGPUTable(const int cell_length, const int bucket_n, int random_seed = -1)
      : _cells_length(cell_length), _bucket_n(bucket_n) {
    // generate hash functions
    if (random_seed == -1)
      random_seed = time(0);
    _rand_seed = random_seed;

    _data = nullptr;
    cudaError_t err_1 =
        cudaMallocManaged(&_data, (sizeof(T) * bucket_n * bucket_cap));
    cudaMemAdvise(_data, (bucket_n * bucket_cap * sizeof(T)),
                  cudaMemAdviseSetAccessedBy, 0);
    cudaMemPrefetchAsync(_data, (bucket_n * bucket_cap * sizeof(T)), 0);
    if (err_1 != cudaSuccess) {
      std::cerr << "CUDA mallocManaged failed for _data: "
                << cudaGetErrorString(err_1) << std::endl;
      return; // Handle allocation failure
    }
    cudaError_t err_3 =
        cudaMemset(_data, 0xFF, (bucket_n * bucket_cap) * sizeof(T));
    if (err_3 != cudaSuccess) {
      std::cerr << "CUDA memset failed for _data: " << cudaGetErrorString(err_3)
                << std::endl;
      return; // Handle allocation failure
    }
    _cells = nullptr;
    cudaError_t err_2 =
        cudaMallocManaged((void **)(&_cells),
                          (cell_length) * sizeof(uint8_t)); // Allocate memory
    cudaMemAdvise(_cells, (cell_length * sizeof(uint8_t)),
                  cudaMemAdviseSetAccessedBy, 0);
    cudaMemPrefetchAsync(_cells, (cell_length * sizeof(uint8_t)), 0);
    if (err_2 != cudaSuccess) {
      std::cerr << "CUDA mallocManaged failed for _cells: "
                << cudaGetErrorString(err_2) << std::endl;
      return; // Handle allocation failure
    }

    // Optionally, initialize to zero (if you want explicit zeroing)
    cudaMemset(_cells, 0, cell_length * sizeof(CELL_T));
    _bucket_n = bucket_n;
    _cells_length = cell_length;
    _size = 0;

    validateSettings();
  }
  ~GPHOSGPUTable() {
    cudaFree(_data);
    cudaFree(_cells);
  }

  void initialize_exp_members(json::value *exp_object,
                              Time_recorder *time_recorder);

  /** Supported operations. */

  // Static operations.
  // Bulk load.
  // GPU memory will be free at the end of each operation.
  // Data are stored on CPU after each operation.
  void insert_vals(const T *const vals, const int n,
                   UnifiedTimeRecorder *recorder = nullptr);
  void insert_vals_CPU(const T *const vals, const int n,
                       const int fail_limit = 8);
  void insert_key_values(const T *const kv_array, const int n,
                         UnifiedTimeRecorder *recorder = nullptr);
  // void delete_vals(const T * const vals, const int n);
  void lookup_vals(const T *const vals, bool *const results, const int n,
                   UnifiedTimeRecorder *recorder = nullptr);
  void lookup_vals_CPU(const T *const vals, bool *const results, const int n);
  void
  lookup_key_return_value_CSI(const typename HalfTypeT<T>::HT *const keys,
                              typename HalfTypeT<T>::HT *const return_values,
                              const int n,
                              UnifiedTimeRecorder *recorder = nullptr);
  void lookup_key_return_value_EXCSI(
      const typename HalfTypeT<T>::HT *const keys, const size_t n,
      std::vector<std::pair<typename HalfTypeT<T>::HT,
                            typename HalfTypeT<T>::HT>> &res_kvs,
      UnifiedTimeRecorder *recorder = nullptr);
  void show_content() const;
  void show_content_kv(bool show_split_kv) const;
  double test_load_factor(int fail_limit = 8, int seed = -1,
                          UnifiedTimeRecorder *recorder = nullptr);
  int size() const {
    return _size;
  } // TODO: insert_vals() has not supported this.
  void clear();

#ifdef CROSS_SM_INDEX
  void lookup_vals_CSI(const T *const vals, bool *const results, const int n,
                       UnifiedTimeRecorder *recorder = nullptr);
#endif
};

// template <typename T, int bucket_cap, int lookup_group_size,
//           int insert_group_size = 8, int virtual_bucket_n = 16>
// remeber to explicit instantiation here
template class GPHOSGPUTable<uint64_t, 32, 4, 8, 8>;
//<uint64_t, 16, 8, 8, 8>;