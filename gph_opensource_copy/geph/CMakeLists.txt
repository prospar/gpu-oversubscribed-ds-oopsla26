cmake_minimum_required (VERSION 3.8 FATAL_ERROR)
project (GPHOS LANGUAGES CUDA CXX)

find_package(CUDA 11.0 REQUIRED)

add_library(geph SHARED src/GPHOS.cu)
    link_directories(/data/srinjoy/gph_opensource_copy_original/common/build)
    target_include_directories(geph PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_include_directories(geph PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
