cmake_minimum_required (VERSION 3.8 FATAL_ERROR)
project (perf LANGUAGES CUDA CXX)

find_package(CUDA REQUIRED)

CPMAddPackage(
  NAME warpcore
  GITHUB_REPOSITORY sleeepyjack/warpcore
  GIT_TAG 1.0.0-alpha.1
) # add warpcore 


include_directories(/usr/local/cuda/samples/common/inc)
include_directories(${CMAKE_SOURCE_DIR}/ThirdParties/cuda-samples/Common)

add_executable(perf perf-final.cu ${BACKWARD_ENABLE})
        target_link_libraries(perf PRIVATE /data/srinjoy/hetero-ds/gph_opensource_copy_original/common/build)
        target_link_libraries(perf PRIVATE warpcore) # for warpcore
        target_link_libraries(perf PRIVATE cudpp_impl)
        target_link_libraries(perf PRIVATE dycuckoo)
        target_link_libraries(perf PRIVATE geph)
        target_link_libraries(perf PRIVATE datasource)
        target_include_directories(perf PRIVATE ${datasource_SOURCE_DIR})
        target_include_directories(perf PRIVATE ${CMAKE_SOURCE_DIR}/dycuckoo/data)
        target_include_directories(perf PRIVATE ${CMAKE_SOURCE_DIR}/dycuckoo/core)
        add_backward(perf)

target_compile_options(perf PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:
        -Xptxas="-dlcm=cg"
        --ptxas-options=-v
        --generate-line-info
        -O3
        --expt-extended-lambda 
        -no-pie
        -fPIC
        # --expt-relaxed-constexpr # will incur error when run with Dycuckoo
>)