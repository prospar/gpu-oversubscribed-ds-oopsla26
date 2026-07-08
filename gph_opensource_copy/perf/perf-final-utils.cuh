#include <cassert>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
std::string getCurrentTimestamp() {
  auto now = std::chrono::system_clock::now();
  std::time_t now_time = std::chrono::system_clock::to_time_t(now);
  char buffer[80];
  std::strftime(buffer, 80, "%Y/%m/%d %H:%M:%S", std::localtime(&now_time));
  return std::string(buffer);
}

template <typename T>
inline __host__ __device__ __uint32_t xxhash32(T value, int seed) {
  __uint32_t h32 = seed + 0x9e3779b9;
  value *= 0x85ebca6b;
  value ^= value >> 13;
  value *= 0xc2b2ae35;
  value ^= value >> 16;
  h32 += value * 0x9e3779b9;
  h32 ^= h32 >> 16;
  h32 *= 0x85ebca6b;
  h32 ^= h32 >> 13;
  return h32;
}

#define remove_ref_cst_pure_decltype(x)                                        \
  std::remove_const_t<std::remove_reference_t<decltype(x)>>
#define _HASH_T xxhash32
#define HASH_CELL_ID(key, rand_seed, used_cell_length)                         \
  (_HASH_T<remove_ref_cst_pure_decltype(key)>(key, rand_seed) %                \
   (used_cell_length))
#define PREPROCES_KEY_ORDER(key, rand_seed, cell_length, sm_cell_block_length) \
  ((int)floor((HASH_CELL_ID(key, rand_seed, (cell_length))) * 1.0 /            \
              sm_cell_block_length))

template <typename T>
void adjust_global(const T *const keys, T *const res_keys, const size_t n) {
  const size_t cell_length = 49152 * 80;
  const size_t block_count = 131072;
  const int rand_seed = 114515;

  size_t sm_cell_block_length = (size_t)ceil(cell_length * 1.0 / block_count);

  size_t *csi_block_size = new size_t[block_count];
  size_t *csi_block_ptrs = new size_t[block_count];
  memset(csi_block_size, 0, sizeof(size_t) * block_count);
  memset(csi_block_ptrs, 0xff, sizeof(size_t) * block_count);

  for (size_t i = 0; i < n; i++) {
    size_t sm_id = PREPROCES_KEY_ORDER(keys[i], rand_seed, cell_length,
                                       sm_cell_block_length);
    csi_block_size[sm_id]++;
  }

  size_t cur = 0;
  for (size_t i = 0; i < block_count; i++) {
    if (csi_block_size[i] > 0) {
      csi_block_ptrs[i] = cur;
      cur += csi_block_size[i];
    }
  }
  memset(csi_block_size, 0, sizeof(size_t) * block_count);

  for (size_t i = 0; i < n; i++) {
    size_t sm_id = PREPROCES_KEY_ORDER(keys[i], rand_seed, cell_length,
                                       sm_cell_block_length);
    size_t loc = csi_block_ptrs[sm_id] + csi_block_size[sm_id];
    res_keys[loc] = keys[i];
    csi_block_size[sm_id]++;
  }
  delete[] csi_block_size;
  delete[] csi_block_ptrs;
}

// read uint32_t file, allocate memory for read data, return data array and write length

uint32_t *read_uint32_datafile(const std::string &file_name, size_t &length) {
  std::cerr << "Reading " << file_name << std::endl;

  // Open the file in binary mode
  std::ifstream file(file_name, std::ios::binary);
  if (!file.is_open()) {
    std::cerr << "Error opening file: " << file_name << std::endl;
    perror("Error details");
    return nullptr;
  }

  // Get the size of the file
  file.seekg(0, std::ios::end);
  size_t file_size = file.tellg();
  file.seekg(0, std::ios::beg);

  // Check that the file size is a multiple of the size of uint32_t
  // std::cerr << "File size: " << file_size << " bytes" << std::endl;
  if (file_size % sizeof(uint32_t) != 0) {
    std::cerr << "File size is not a multiple of uint32_t size!" << std::endl;
    return nullptr;
  }

  // Calculate the number of uint32_t elements
  length = file_size / sizeof(uint32_t);

  // Allocate memory for the data array
  uint32_t *data_array;
  cudaError_t err = cudaMallocManaged((void **)&data_array, sizeof(uint32_t) * length);
  if (err != cudaSuccess) {
    std::cerr << "CUDA malloc failed: " << cudaGetErrorString(err) << std::endl;
    return nullptr;
  }

  // Read the data into the array
  file.read(reinterpret_cast<char *>(data_array), file_size);

  // Check for errors during the read
  if (!file) {
    std::cerr << "Error reading file: " << file_name << std::endl;
    std::cerr << "Bytes read: " << file.gcount() << " of " << file_size << std::endl;
    cudaFree(data_array);  // Free memory if the read failed
    return nullptr;
  }

  // Close the file
  file.close();

  printf("File read successfully: Length: %lu, Data size: %lu\n", length, length);

  return data_array;
}

class DatasetManager {
private:
  std::string dataset_name;
  std::string workload_type;
  uint32_t *insert_keys;
  uint32_t *insert_vals;
  uint32_t *lookup_keys;
  size_t insert_len;
  size_t lookup_len;

public:
  DatasetManager(const std::string &dataset_name, std::string pos)
      : dataset_name(dataset_name) {
    // Read insert_keys
    insert_len = 0;
    lookup_len = 0;
    insert_keys = read_uint32_datafile(
        fmt::format("/data/srinjoy/hetero-ds/gph_opensource_copy_original/"
                    "datasource/insert_trace-50e7-100-add-no-dup-MONOTONIC_INCREASE.bin",
                    dataset_name),
        insert_len);

    // Read insert_vals
    insert_vals = read_uint32_datafile(
        fmt::format("/data/srinjoy/hetero-ds/gph_opensource_copy_original/"
                    "datasource/insert_trace-50e7-100-add-no-dup-MONOTONIC_INCREASE.bin",
                    dataset_name),
        insert_len);

    // Define workload_type
    workload_type = fmt::format("workload_pos{}_size400000000", pos);

    // Read lookup_keys
    uint32_t *raw_lookup_keys = read_uint32_datafile(
        fmt::format("/data/srinjoy/hetero-ds/gph_opensource_copy_original/"
                    "datasource/insert_trace-50e7-100-add-no-dup-MONOTONIC_INCREASE.bin",
                    dataset_name, workload_type),
        lookup_len);
         
    cudaMallocManaged((void **)&lookup_keys, sizeof(uint32_t) * lookup_len);
    adjust_global(raw_lookup_keys, lookup_keys, lookup_len);
    cudaFree(raw_lookup_keys);
  }

  void enableQuickCheck() const {
    for (size_t i = 0; i < insert_len; i++) {
      insert_vals[i] = insert_keys[i] + 1;
    }
  }

  ~DatasetManager() {
    delete[] insert_keys;
    delete[] insert_vals;
    delete[] lookup_keys;
  }
  std::string getDatasetName() const { return dataset_name; }
  std::string getWorkloadType() const { return workload_type; }
  uint32_t *getInsertKeys() const { return insert_keys; }

  uint32_t *getInsertVals() const { return insert_vals; }

  uint32_t *getLookupKeys() const { return lookup_keys; }

  size_t getInsertLen() const { return insert_len; }

  size_t getLookupLen() const { return lookup_len; }
};

#define EXP_MODE_NO_CHECK 1
#define EXP_MODE_CHECK 2
#define EXP_MODE_EFFECTIVE_LOAD_FACTOR_TEST 3
