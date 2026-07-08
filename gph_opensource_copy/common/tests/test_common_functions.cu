#include <stdint.h> // for uint32_t
#include "gtest/gtest.h"
#include <fmt/core.h>

unsigned getWarpMask(int group_size, int thread_id) {
    if (group_size == 32) return 0xffffffff;
    return ((0x1 << group_size) - 1) << (((thread_id % 32) / group_size) * group_size);
}


// uint32_t getSequenceOfOnes(int length) {
//     if (length <= 0 || length > 32) {
//         printf("Invalid length entered.\n");
//         return 0;
//     }

//     uint32_t result = (1 << length) - 1;
//     return result;
// }


TEST(TestCommonFunctions, getWarpMask_test) {
    ASSERT_EQ(0xffffffff, getWarpMask(32, 0));
    ASSERT_EQ(0xffffffff, getWarpMask(32, 4));
    ASSERT_EQ(0xffffffff, getWarpMask(32, 6));
    ASSERT_EQ(0xffffffff, getWarpMask(32, 16));
    ASSERT_EQ(0xffffffff, getWarpMask(32, 31));
    ASSERT_EQ(0xffffffff, getWarpMask(32, 25));

    ASSERT_EQ(0xffff, getWarpMask(16, 0));
    ASSERT_EQ(0xffff, getWarpMask(16, 4));
    ASSERT_EQ(0xffff, getWarpMask(16, 6));
    ASSERT_EQ(0xffff0000, getWarpMask(16, 16));
    ASSERT_EQ(0xffff0000, getWarpMask(16, 31));
    ASSERT_EQ(0xffff0000, getWarpMask(16, 25));

    ASSERT_EQ(0xff, getWarpMask(8, 0));
    ASSERT_EQ(0xff, getWarpMask(8, 4));
    ASSERT_EQ(0xff, getWarpMask(8, 6));
    ASSERT_EQ(0xff, getWarpMask(8, 7));
    ASSERT_EQ(0xff00, getWarpMask(8, 8));
    ASSERT_EQ(0xff00, getWarpMask(8, 15));
    ASSERT_EQ(0xff0000, getWarpMask(8, 16));
    ASSERT_EQ(0xff0000, getWarpMask(8, 23));
    ASSERT_EQ(0xff000000, getWarpMask(8, 25));
    ASSERT_EQ(0xff000000, getWarpMask(8, 31));


    ASSERT_EQ(0xf, getWarpMask(4, 0));
    ASSERT_EQ(0xf0, getWarpMask(4, 4));
    ASSERT_EQ(0xf0, getWarpMask(4, 6));
    ASSERT_EQ(0xf0000, getWarpMask(4, 16));
    ASSERT_EQ(0xf0000000, getWarpMask(4, 31));
}