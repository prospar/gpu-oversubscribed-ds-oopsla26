cmake_minimum_required (VERSION 3.8 FATAL_ERROR)
project (cudppImpl LANGUAGES CUDA CXX)

find_package(CUDA REQUIRED)

add_library(cudpp_impl SHARED src/static-demo.cu)
    target_link_libraries(cudpp_impl PUBLIC common)
    target_link_libraries(cudpp_impl PUBLIC random-gen)
    target_compile_options(cudpp_impl PRIVATE -Wall -Wextra)
    target_include_directories(cudpp_impl PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)

# hi 