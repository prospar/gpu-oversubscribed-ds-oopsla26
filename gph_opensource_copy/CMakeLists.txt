cmake_minimum_required (VERSION 3.8 FATAL_ERROR)

set(CMAKE_CUDA_COMPILER /usr/local/cuda/bin/nvcc)
set(CMAKE_CUDA_STANDARD 17) # WarpCore needs 14
set(CMAKE_CUDA_STANDARD_REQUIRED ON) 
set(CMAKE_CUDA_FLAGS ${CMAKE_CUDA_FLAGS} -lineinfo)
# set(CMAKE_CUDA_FLAGS ${CMAKE_CUDA_FLAGS} "--maxrregcount=40 -Xptxas -O3 -lineinfo -gencode=arch=compute_70,code=sm_70 -gencode=arch=compute_70,code=compute_70") # release

# set(CMAKE_CUDA_FLAGS ${CMAKE_CUDA_FLAGS} "-Xptxas -dlcm=cg --generate-line-info -O3 -expt-extended-lambda") # change to CMake of perf
set(CMAKE_CUDA_ARCHITECTURES 70)

project (gpuhashbenchmark-root LANGUAGES CUDA CXX)

# find_package(CUDA REQUIRED) # not necessary after 3.10
include(FetchContent)

find_package(fmt REQUIRED)

# FetchContent_Declare(
#   fmt
#   GIT_REPOSITORY https://github.com/fmtlib/fmt
#   GIT_TAG        e69e5f977d458f2650bb346dadf2ad30c5320281
# ) # 10.2.1
# FetchContent_MakeAvailable(fmt)

file(
  DOWNLOAD
  https://github.com/cpm-cmake/CPM.cmake/releases/download/v0.40.8/CPM.cmake
  ${CMAKE_CURRENT_BINARY_DIR}/cmake/CPM.cmake
  EXPECTED_HASH SHA256=78ba32abdf798bc616bab7c73aac32a17bbd7b06ad9e26a6add69de8f3ae4791
)
include(${CMAKE_CURRENT_BINARY_DIR}/cmake/CPM.cmake)

option(CMAKE_VERBOSE_MAKEFILE ON)

set(CMAKE_BUILD_TYPE "Debug")

# Add FetchContent with specific source directories:
include(FetchContent)

# Configor
FetchContent_Declare(
  configor
  SOURCE_DIR ${CMAKE_SOURCE_DIR}/ThirdParties/configor
  GIT_REPOSITORY https://github.com/Nomango/configor.git
  GIT_TAG        master
)
FetchContent_MakeAvailable(configor)

# # GoogleTest
# FetchContent_Declare(
#   googletest
#   SOURCE_DIR ${CMAKE_SOURCE_DIR}/ThirdParties/googletest
#   GIT_REPOSITORY https://github.com/google/googletest.git
#   GIT_TAG        release-1.10.0
# )
# FetchContent_MakeAvailable(googletest)

# backward-cpp
FetchContent_Declare(
  backward-cpp
  SOURCE_DIR ${CMAKE_SOURCE_DIR}/ThirdParties/backward-cpp
  GIT_REPOSITORY https://github.com/bombela/backward-cpp.git
  GIT_TAG        v1.6
)
FetchContent_MakeAvailable(backward-cpp)

# FetchContent_Declare(
#   dycuckoo
#   GIT_REPOSITORY https://github.com/zhuqiweigit/DyCuckoo.git
#   GIT_TAG master
#   SOURCE_DIR ${CMAKE_SOURCE_DIR}/dycuckoo
#   SOURCE_SUBDIR dynamicHash  # This specifies which subdirectory to use
# )
# FetchContent_MakeAvailable(dycuckoo)

# Check if the directory exists first
# if(NOT EXISTS "/usr/local/cuda/samples/common/inc")
#     message(FATAL_ERROR "dycuckoo dependency CUDA samples include directory not found: /usr/local/cuda/samples/common/inc")
# endif()

add_subdirectory(dycuckoo)
add_subdirectory(cudppImpl)
add_subdirectory(datasource)
add_subdirectory(common)
add_subdirectory(geph)
add_subdirectory(perf)