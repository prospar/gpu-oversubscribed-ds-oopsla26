#include <iostream>
#include <string>
#include "GPHOS.cuh"
#include <fmt/core.h>
#include <fmt/color.h>
#include <algorithm>

#include "halfType.cuh"


using namespace std;

const int MAX_INTS = 40000000; // maximum number of integers per line

using DEMO_T_TYPE = uint64_t;
using DEMO_HT_TYPE = uint32_t;

enum class Instruction
{
    INSERT, // instruction type "insert"
    FIND,   // instruction type "find"
    LOAD_FACTOR,
    SET_lookup_group_size
};

void parse_line(string line, int &instruction, DEMO_T_TYPE *kv_array, DEMO_HT_TYPE *keys, int &num_ints)
{
    char instr = line[0];                                                           // get the instruction character
    // instruction = instr == 'i' ? (int)Instruction::INSERT : (int)Instruction::FIND; // convert to the enum value
    bool inputRange = false;

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
            instruction = (int)Instruction::SET_lookup_group_size;
            break;
        case 'r':
            instruction = (int)Instruction::INSERT;
            inputRange = true;
            break;
        case 'o':
            instruction = (int)Instruction::FIND;
            inputRange = true;
            break;
        default:
            instruction = (int)Instruction::FIND;
            break;
    }

    DEMO_HT_TYPE num;
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
        // sscanf(line.substr(start, end - start).c_str(), "%u", &num);
        std::istringstream iss(line.substr(start, end - start).c_str());
        iss >> num;
        keys[num_ints] = num;
        kv_array[num_ints++] = combineKV<DEMO_T_TYPE>(num, num+1);
        i = end + 1; // jump to the position after the last space found
    }
    DEMO_HT_TYPE st = keys[0];
    DEMO_HT_TYPE ed = keys[1];
    num_ints = 0;
    if (inputRange) {
        for (DEMO_HT_TYPE i = st; i <= ed; i++) {
            keys[i] = i;
            kv_array[i] = combineKV<DEMO_T_TYPE>(i, i+1);
            num_ints += 1;
        }
    } 
    fmt::print("{} numbers are read.\n", num_ints);
}

/**
 * input example:
 * i 1 2 3 4 5 // insert 1 2 3 4 5
 * f 3 4 5 6   // lookup 3 4 5 6
 * > 3:y 4:y 5:y 6:n
 */

DEMO_T_TYPE kv_array[MAX_INTS];
DEMO_HT_TYPE keys[MAX_INTS];
DEMO_HT_TYPE results[MAX_INTS];
// bool results_gt[MAX_INTS];
char line_buffer[MAX_INTS * 10];


// template <typename T, int bucket_cap, int lookup_group_size,
//           int insert_group_size = 8, int virtual_bucket_n = 16>
// template class GPHOSGPUTable<uint64_t, 8, 8, 8, 4>;
int main()
{
    const int cell_length = 2 * 49152 * 80;
    const int bucket_cap = 16;
    const int lookup_group_size = 8;
    const int bucket_n = 8388608;
    const int virtual_bucket_n = 8;
    GPHOSGPUTable<DEMO_T_TYPE, bucket_cap, lookup_group_size, 8, virtual_bucket_n> hash_table(
        cell_length,    
        bucket_n,
        218747798);
    // hash_table.show_content();

    fmt::print("GPUGPHOS hash table initialization complete, please input \"[i|f] <input1> [<input2> ...]\"\n");
    fmt::print(fg(fmt::color::crimson) | fmt::emphasis::bold, "WARNING: If you use Windows console for input, please note that there is a limit on the length of each command line, and any characters beyond the limit may be discarded without warning. Please pay attention to the feedback information after each operation to check for any issues. For inputs longer than 2000 characters, it is recommended to use file input.\n");
    int num_ints;
    int instruction; // each instruction consists of 2 ints: type and count

    string line; 
    int yescount = 0;
    int nocount = 0;
    while (getline(cin, line))
    { 
        parse_line(line, instruction, kv_array, keys, num_ints);

        switch (instruction)
        {
        case (int)Instruction::INSERT:
            cout << "Start insert..." << endl;
            // hash_table.insert_vals(kv_array, num_ints);
            hash_table.insert_key_values(kv_array, num_ints);
            cout << "Insert complete." << endl;
            break;
        case (int)Instruction::FIND:
            // hash_table.lookup_vals(kv_array, results, num_ints);
            hash_table.lookup_key_return_value_CSI(keys, results, num_ints);
            yescount = 0;
            nocount = 0;
            for (int i = 0; i < num_ints; i++){
                if (results[i] == keys[i]+1){
                    ++yescount;
                    // fmt::print("{}:{} ", keys[i], results[i]);
                }
                else {
                    ++nocount;
                    // fmt::print("{}:{} ", keys[i], results[i]);
                }
            }
            // hash_table.show_content_kv(true);
            fmt::print(fg(fmt::color::red) | fmt::emphasis::bold, "\nYes count {}, No count {}\n", yescount, nocount);
            fmt::print("\n");
            cout << endl;
            break;
        default:
            cout << "Unknown instruction" << endl;
        }
        fmt::print("Waiting for new input......");
    }

    return 0;
}