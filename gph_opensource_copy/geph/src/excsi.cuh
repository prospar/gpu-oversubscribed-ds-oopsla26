
#define PRE_COUNTER_TYPE uint32_t
// #define EXCSI_DEBUG

template <typename T, int bucket_cap, int lookup_group_size,
          int insert_group_size, int virtual_bucket_n>
void GPHOSGPUTable<T, bucket_cap, lookup_group_size, insert_group_size,
                      virtual_bucket_n>::lookup_key_return_value_EXCSI(const typename HalfTypeT<T>::HT *const keys,
                                                         const size_t n,
                                                         std::vector<std::pair<typename HalfTypeT<T>::HT,
                                                         typename HalfTypeT<T>::HT>>& res_kvs,
                                                         UnifiedTimeRecorder *recorder)
{
  int sm_cell_block_length = (int)ceil(_cells_length * 1.0 / BLOCK_COUNT);

  using HT = typename HalfTypeT<T>::HT;
  size_t key_size_bytes = sizeof(HT);

#ifdef EXCSI_DEBUG
size_t pre_block_num = 80;
size_t pre_thread_per_block = 256;
size_t subregion_num = 768;
double space_tolerance_ratio = 1.5;
#else
  size_t pre_block_num = 80;
  size_t pre_thread_per_block = 1024;
  size_t subregion_num = 24576;
  double space_tolerance_ratio = 2.0;
#endif

  size_t lookup_block_num = BLOCK_COUNT;
  size_t key_n = n;
  size_t shared_per_block_bytes = 96 * 1024;
  size_t counter_type_bytes = sizeof(PRE_COUNTER_TYPE);
  size_t compress_num = lookup_block_num / subregion_num;
  size_t region_num = pre_block_num;
  size_t keys_per_pre_block = (size_t)(ceil(key_n * 1.0 / pre_block_num));
  size_t region_len = (size_t)(ceil(ceil(key_n * 1.0 / pre_block_num / subregion_num) * space_tolerance_ratio) * subregion_num);
  size_t subregion_len = region_len / subregion_num;
  size_t total_regions_len = region_len * pre_block_num;

  vclog(INFO, "EXCSI INFOkey_n\t{}\n\tkey_size_bytes\t{}\n\tpre_block_num\t{}\n\tpre_thread_per_block\t{}\n\tshared_per_block_bytes\t{}\n\tcounter_type_bytes\t{}\n\t\subregion_num\t{}\n\tlookup_block_num\t{}\n\tcompress_num\t{}\n\tspace_tolerance_ratio\t{}\n\tregion_num\t{}\n\tkeys_per_pre_block\t{}\n\tregion_len\t{}\n\tsubregion_len\t{}\n\ttotal_regions_len\t{}",key_n,key_size_bytes,pre_block_num,pre_thread_per_block,shared_per_block_bytes,counter_type_bytes,subregion_num,lookup_block_num,compress_num,space_tolerance_ratio,region_num,keys_per_pre_block,region_len,subregion_len,total_regions_len);

  assert(lookup_block_num % subregion_num == 0);
  assert(shared_per_block_bytes / counter_type_bytes >= subregion_num);
  assert(counter_type_bytes >= 4);

  HT * d_keys;
  HT * d_regions;
  HT * d_res_regions; 

  HT * h_regions = new HT[total_regions_len];
  HT * h_res_regions = new HT[total_regions_len];

  cudaMalloc((void **)&d_keys, n * sizeof(HT));
  cudaMalloc((void **)&d_regions, total_regions_len * sizeof(HT));
  cudaMalloc((void **)&d_res_regions, total_regions_len * sizeof(HT));
  cudaMemcpy(d_keys, keys, n * sizeof(HT), cudaMemcpyHostToDevice);

  cudaMemset(d_regions, 0, total_regions_len * sizeof(HT));
  cudaMemset(d_res_regions, 0, total_regions_len * sizeof(HT));

  if (recorder)
  {
    recorder->start_timer("preprocess", true);
  }

  cudaFuncSetAttribute(adjust_EXCSI<HT>, cudaFuncAttributeMaxDynamicSharedMemorySize, shared_per_block_bytes);
  adjust_EXCSI<HT><<<pre_block_num, pre_thread_per_block, shared_per_block_bytes>>> 
  (
    d_keys, n, d_regions, total_regions_len, keys_per_pre_block, compress_num, shared_per_block_bytes,
    region_len, subregion_len, _rand_seed, _cells_length, sm_cell_block_length
  );

#ifdef EXCSI_DEBUG
  cudaDeviceSynchronize();

  if (recorder)
  {
    recorder->finish_timer("preprocess");
  }

  cudaMemcpy(h_regions, d_regions, total_regions_len * sizeof(HT), cudaMemcpyDeviceToHost);
  int max_cnt = 0;
  for (size_t region_id = 0; region_id < region_num; region_id ++) {
    // fmt::print("Region {}:\n",region_id);
    for (size_t subregion_id = 0; subregion_id < subregion_num; subregion_id++) {
      // fmt::print("\tSubregion {}: ", subregion_id);
      int cnt = 0; 
      for (size_t offset = 0; offset < subregion_len; offset++) {
        HT key = h_regions[region_id * region_len + subregion_id * subregion_len + offset];
        if (key > 0) {
          // fmt::print("{}({}) ", key, KEY_TO_SM_ID(key, _rand_seed, _cells_length, sm_cell_block_length));
          cnt ++;
        } else {
          // fmt::print("{} ", 0);
        }
      }
      max_cnt = max(max_cnt, cnt);
      // fmt::print("\n");
    }
    // fmt::print("\n");
  }
  fmt::print("MAX_COUNT = {}, subregion_len = {}\nFULLFIL_RATE {}\n", max_cnt, subregion_len, max_cnt*1.0/subregion_len);
  
  delete [] h_regions;
  delete [] h_res_regions;
  cudaFree(d_keys);
  cudaFree(d_regions);
  cudaFree(d_res_regions);
  return;
#endif

  cudaError_t cudaerr = cudaDeviceSynchronize();
  gpuErrchk(cudaerr);

  if (recorder)
  {
    recorder->finish_timer("preprocess");
  }

  cudaFree(d_keys);

  // Allocate GPU memory space.
  T *d_data;
  CELL_T *d_cells;


  cudaMalloc((void **)&d_data, _bucket_n * bucket_cap * sizeof(T));
  cudaMalloc((void **)&d_cells,(_cells_length) * sizeof(CELL_T));

  cudaMemcpy(d_data, _data, _bucket_n * bucket_cap * sizeof(T),cudaMemcpyHostToDevice);
  cudaMemcpy(d_cells, _cells,(_cells_length) * sizeof(CELL_T),cudaMemcpyHostToDevice);
  

  cudaStream_t stream;
  cudaStreamCreate(&stream);

  if ((size_t)((sm_cell_block_length) * sizeof(CELL_T)) > (size_t)SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE)
  {
    panic("Too large index size.");
  } else {
    vclog(INFO, "cell index per block length {} ({} bytes)", sm_cell_block_length, (sm_cell_block_length) * sizeof(CELL_T));
  }

  if (recorder)
  {
    recorder->start_timer("lookup_kernel", true);
  }
  // lauch kernel
  GPHOSGPUTableLookupKeyReturnValueEXCSIKernel<T, bucket_cap, lookup_group_size, virtual_bucket_n>
      <<<BLOCK_COUNT, GPHOS_BLOCK_SIZE,
         min((size_t)((sm_cell_block_length) * sizeof(CELL_T)),
             (size_t)SHARED_MEMORY_PER_BLOCK_FOR_INDEX_SIZE),
         stream>>>(d_regions, d_res_regions, total_regions_len,
            compress_num, region_len, region_num, subregion_len, 
            d_data, _bucket_n, d_cells, _cells_length, _rand_seed);
  cudaerr = cudaDeviceSynchronize();
  gpuErrchk(cudaerr);

  if (recorder)
  {
    recorder->finish_timer("lookup_kernel");
  }

  cudaMemcpy(_data, d_data, _bucket_n * bucket_cap * sizeof(T),cudaMemcpyDeviceToHost);
  cudaMemcpy(_cells, d_cells,((_cells_length)) * sizeof(CELL_T),cudaMemcpyDeviceToHost);

  cudaMemcpy(h_regions, d_regions, total_regions_len * sizeof(HT), cudaMemcpyDeviceToHost);
  cudaMemcpy(h_res_regions, d_res_regions, total_regions_len * sizeof(HT), cudaMemcpyDeviceToHost);

  for (size_t i = 0; i < total_regions_len; i++) {
    if (h_regions[i] > 0) {
        res_kvs.push_back(std::make_pair(h_regions[i], h_res_regions[i]));
    }
  }


  delete [] h_regions;
  delete [] h_res_regions;
  cudaFree(d_data);
  cudaFree(d_cells);
  cudaFree(d_regions);
  cudaFree(d_res_regions);
}


template <typename HT>
__global__ void adjust_EXCSI(
  HT *keys, size_t key_n, // input 
  HT *regions, size_t regions_n, // output
  size_t keys_per_pre_block, 
  size_t compress_num, 
  size_t shared_per_block_bytes,
  size_t region_len,
  size_t subregion_len,
  const int rand_seed,
  const int cell_length,
  const int sm_cell_block_length
) 
{
  int tid = threadIdx.x;
  int bid = blockIdx.x;

  extern __shared__ PRE_COUNTER_TYPE counter[];
  
  // initialize shared memory to all zeros.
  size_t counter_num = shared_per_block_bytes / sizeof(PRE_COUNTER_TYPE);
  for (int i = tid; i < counter_num; i += blockDim.x) {
    counter[i] = 0;
  }
  __syncthreads();

  size_t start_addr = bid * keys_per_pre_block;
  size_t end_addr = min((bid + 1) * keys_per_pre_block, key_n);

  for (size_t i = start_addr + tid; i < end_addr; i += blockDim.x) {
    HT key = keys[i];
    size_t lookup_block_id = KEY_TO_SM_ID(key, rand_seed, cell_length, sm_cell_block_length);
    size_t subregion_id = lookup_block_id / compress_num;
    PRE_COUNTER_TYPE offset = atomicAdd(counter + subregion_id, 1);
    // PRE_COUNTER_TYPE offset = xxhash32<uint32_t>(key, tid) % subregion_len;
    size_t target_loc = bid * region_len + subregion_id * subregion_len + offset;
    assert(target_loc < (bid * region_len + (subregion_id+1) * subregion_len));
    regions[target_loc] = key;
    // regions[tid % (bid * region_len + (subregion_id+1) * subregion_len)] = key;
  }
}


template <typename T, int bucket_cap, int lookup_group_size,
          int virtual_bucket_n>
__global__ void
GPHOSGPUTableLookupKeyReturnValueEXCSIKernel(const typename HalfTypeT<T>::HT * regions,
                                    typename HalfTypeT<T>::HT * res_regions, 
                                    size_t total_regions_len,
                                    size_t compress_num, 
                                    size_t region_len, size_t region_num,
                                    size_t subregion_len,
                                    T *const data,
                                    const int bucket_n, const CELL_T *cells,
                                    const int cell_length,
                                    const int rand_seed)
{
  using HT = typename HalfTypeT<T>::HT;
  // compile-time const
  constexpr int TOTAL_TURN = bucket_cap / lookup_group_size;
  constexpr int KV_SIZE = sizeof(T);
  constexpr int VECTOR_LEN = (16 < (TOTAL_TURN * KV_SIZE) ? 16 : (TOTAL_TURN * KV_SIZE)) / KV_SIZE;
  using V = CUDAVectorType_t<T, VECTOR_LEN>;
  int groupLane = threadIdx.x % lookup_group_size; 
  int groupId = threadIdx.x / lookup_group_size;
  int groupN = blockDim.x / lookup_group_size;
  int lookup_block_id = blockIdx.x;
  extern __shared__ CELL_T shared[];
  unsigned group_mask = getWarpMask(lookup_group_size, threadIdx.x);
  int sm_cell_block_length = (int)ceil(cell_length * 1.0 / BLOCK_COUNT);

  // copy cells array to shared mem
  int copyId = threadIdx.x;

  while (copyId < sm_cell_block_length && lookup_block_id * sm_cell_block_length + copyId < cell_length) // cell_length
  {
    shared[copyId] = cells[lookup_block_id * sm_cell_block_length + copyId];
    copyId += blockDim.x;
  }

  __syncthreads();
  // __threadfence_block();

  size_t subregion_id = lookup_block_id / compress_num;
  size_t v_total = subregion_len * region_num;

#ifdef NKPR
  size_t v_group_len = (size_t)ceil(v_total * 1.0 / groupN);
  size_t v_group_start = groupId * v_group_len;
  size_t v_group_end = min((groupId+1) * v_group_len, v_total);
  
  size_t v_head = v_group_start;
  while (true) {
    if (v_head >= v_group_end) break;
    size_t region_head = v_head / subregion_len;
    size_t offset_head = v_head % subregion_len;
    size_t offset_lane = groupLane + offset_head;
    size_t target_loc = region_head*region_len+subregion_id*subregion_len+offset_lane;
    assert(target_loc < total_regions_len);

    HT own_key = 0;
    HT own_value = 0;
    if (offset_lane < subregion_len) {
        own_key = regions[target_loc];
    }
    
    bool early_break = false;
    bool skipped = false;
    for (int j = 0; j < lookup_group_size; j++)
    {
        HT key = __shfl_sync(group_mask, own_key, j, lookup_group_size);
        if (key == 0) {
            early_break = true;
            break;
        }
        // Get the cell id
        int globalCellId = HASH_CELL_ID(key, rand_seed, (cell_length));
        int belongsToBlockId = globalCellId / sm_cell_block_length;
        if (lookup_block_id == belongsToBlockId) {
          int localCellId = CELL_LOCAL_ID(globalCellId, lookup_block_id, sm_cell_block_length);
          HT lookup_res = lookupBucketForTargetKeyReturnValue<T, bucket_cap, lookup_group_size,virtual_bucket_n>(
              key, data, bucket_n, globalCellId, localCellId, cells,
              cell_length, groupLane, group_mask, rand_seed); 
          if (j == groupLane)
            own_value = lookup_res;
        } else {
          if (j == groupLane) {
            skipped = true;
          }
        }
    }
    if (own_key > 0 && !skipped) {
        res_regions[target_loc] = own_value;
    }
 
    if (early_break) v_head = (region_head + 1) * subregion_len;
    else v_head += lookup_group_size;
  }
#else
  size_t v_group_len = (size_t)ceil(v_total * 1.0 / groupN);
  size_t v_group_start = groupId * v_group_len;
  size_t v_group_end = min((groupId+1) * v_group_len, v_total);

  size_t v_head = v_group_start;
  while (true) {
      if (v_head >= v_group_end) break;
      size_t region_head = v_head / subregion_len;
      size_t offset_head = v_head % subregion_len;
      size_t target_loc = region_head*region_len+subregion_id*subregion_len+offset_head;
      
      HT key = 0;
      HT value = 0;
      if (groupLane == 0) {
          key = regions[target_loc];
      }
      key = __shfl_sync(group_mask, key, 0, lookup_group_size);
      if (key == 0) {
          v_head = (region_head + 1) * subregion_len;
      } else {
          int globalCellId = HASH_CELL_ID(key, rand_seed, (cell_length));
          int belongsToBlockId = globalCellId / sm_cell_block_length;
          if (belongsToBlockId == lookup_block_id) {
            int localCellId = CELL_LOCAL_ID(globalCellId, lookup_block_id, sm_cell_block_length);
            HT lookup_res = lookupBucketForTargetKeyReturnValue<T, bucket_cap, lookup_group_size, virtual_bucket_n>(
                key, data, bucket_n, globalCellId, localCellId, cells, cell_length, groupLane,
                group_mask, rand_seed);
            if (groupLane == 0)
            { 
                res_regions[target_loc] = lookup_res;
            }
          }
          v_head += 1;
      }    
  }
#endif
}