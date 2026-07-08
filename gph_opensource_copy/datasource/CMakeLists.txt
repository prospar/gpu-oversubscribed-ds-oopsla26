cmake_minimum_required (VERSION 3.8 FATAL_ERROR)
project (datasource LANGUAGES CUDA CXX)

find_package(CUDA REQUIRED)

add_library(random-gen SHARED mt19937ar.cpp random_numbers.cpp)
    target_include_directories(random-gen PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/)

add_library(datasource SHARED data_source.cu)
    target_include_directories(datasource PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/)
    target_link_libraries(datasource PUBLIC common)