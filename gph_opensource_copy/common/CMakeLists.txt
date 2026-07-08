cmake_minimum_required (VERSION 3.8 FATAL_ERROR)
project (common LANGUAGES CUDA CXX)

find_package(CUDA REQUIRED)
find_package(fmt REQUIRED)
add_library(common SHARED Exp_batch_result_holder.cu)
    target_include_directories(common PUBLIC ./include)
    target_link_libraries(common PUBLIC fmt::fmt)
    target_include_directories(common PUBLIC ${configor_SOURCE_DIR}/include)

# add_executable(test_time_recorder tests/test_time_recorder.cu)
#     target_link_libraries(test_time_recorder common gtest gtest_main)

# add_test(NAME test_time_recorder COMMAND test_time_recorder)

# add_executable(test_common_functions tests/test_common_functions.cu)
#     target_link_libraries(test_common_functions common gtest gtest_main)

# add_test(NAME test_common_functions COMMAND test_common_functions)
