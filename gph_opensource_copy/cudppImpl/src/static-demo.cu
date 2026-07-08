#include <iostream>
#include <string>
#include <fmt/core.h>
#include <fmt/color.h>
#include <algorithm>
#include <limits>


#include "cuckoo-cuda-naive.cuh"
#include "Exp_batch_result_holder.cuh"
#include "random_numbers.h"
#include "mt19937ar.h"

using namespace std;

/**
 * input example:
 * i 1 2 3 4 5 // insert 1 2 3 4 5
 * f 3 4 5 6   // lookup 3 4 5 6
 * > 3:y 4:y 5:y 6:n
 */
namespace ManualTest {

#ifdef BEFORE
const int MAX_INTS = 10000; // maximum number of integers per line


unsigned int_arr[MAX_INTS];
bool results[MAX_INTS];
bool results_gt[MAX_INTS];
char line_buffer[MAX_INTS * 10];

const int each_table_size = 10;
const int evict_bound = 4 * ceil(log2((double) each_table_size )); // evict_number = evict_bound * num_funcs
const int num_funcs = 4; // 几个func，几个table


    enum class Instruction
{
    INSERT, // instruction type "insert"
    FIND,   // instruction type "find"
    LOAD_FACTOR,
    SET_GROUP_SIZE
};

void parse_line(string line, int &instruction, int &num_ints)
{
    char instr = line[0];                                                           // get the instruction character
    // instruction = instr == 'i' ? (int)Instruction::INSERT : (int)Instruction::FIND; // convert to the enum value

    switch (instr) {
        case 'i':
            instruction = (int)Instruction::INSERT;
            break;
        case 'f':
            instruction = (int)Instruction::FIND;
            break;
        case 'l':
            instruction = (int)Instruction::LOAD_FACTOR;
            break;
        case 's':
            instruction = (int)Instruction::SET_GROUP_SIZE;
            break;
        default:
            instruction = (int)Instruction::FIND;
            break;
    }

    int32_t num;
    int i = 2; // skip past instruction character and space
    num_ints = 0;
    while (num_ints < MAX_INTS && i < line.length())
    {                                                  // make sure i is within bounds
        size_t start = line.find_first_not_of(" ", i); // find the first non-space character after index i
        if (start == string::npos)
            break;                          // exit loop if no non-space characters were found
        size_t end = line.find(" ", start); // find the position of the next space character after start
        if (end == string::npos)
            end = line.length(); // if no more spaces, consider everything from start to the end of the line
        sscanf(line.substr(start, end - start).c_str(), "%d", &num);
        int_arr[num_ints++] = (unsigned) num;
        i = end + 1; // jump to the position after the last space found
    }
    fmt::print("{} numbers are read.\n", num_ints);
}
#endif

};

class AutoStaticTest {
};


// int main()
// {
//     AutoStaticTest st_test;
//     st_test.naive_static_build_find_test();
// }