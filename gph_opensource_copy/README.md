# GPH  
**GPH** is a **G**PU-based **P**erfect **H**ash Table implementation, accompanying the paper *GPH: An Efficient and Effective Perfect Hashing Scheme for GPU Architectures*.  

## Features  
- **Perfect Hashing**: Ensures exactly one lookup probe.  
- **Efficient Lookup**: Optimizes throughput via vectorization and instruction-level parallelism.  
- **Parallel Insertion**: Supports GPU-accelerated parallel insertions.  

## Quickstart  
**Prerequisites**:  
- CUDA-capable GPU with compute capability 7.0
- CUDA Toolkit 12.6+  
- {fmt} libarary, `sudo apt install libfmt-dev`

```bash
cd gph_opensource  
cd datasource
python generate_random_num.py
python generate_pos_neg_workload.py
cd ../
cmake -B build  
python perf/gph_autoexp.py  # To find optimal configuration
```  

The result can be found in the folder indicated by "outputDir" in perf/gph_autoexp_comp_v3.json.

This is a pre-release version, and subsequent code may be implemented to achieve higher usability.


## Docker
sudo docker pull sameli/manylinux_2_34_x86_64_cuda_12.8
sudo docker run -it --name my_manylinux_container -v /./gph_opensource_copy:/home/gph_opensource_copy sameli/manylinux_2_34_x86_64_cuda_12.8 /bin/bash
cd /home/gph_opensource_copy
python3 generate_random_num.py
python3 generate_pos_neg_workload.py
dnf -y install fmt-devel
cmake -B build
cmake --build build