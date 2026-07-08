// -------------------------------------------------------------
// cuDPP -- CUDA Data Parallel Primitives library
// -------------------------------------------------------------
// $Revision: $
// $Date: $
// -------------------------------------------------------------
// This source code is distributed under the terms of license.txt in
// the root directory of this source distribution.
// -------------------------------------------------------------

#include "random_numbers.h"

#include <string.h>  // memcpy

#include <algorithm>
#include <cstdio>

#include <iostream>
#include <fstream>
#include <unordered_map>
#include <string>
#include <random>

#include "mt19937ar.h"

void GetUniqueRandomNumbers(unsigned *random_numbers,
                                  const unsigned num_random_numbers,
                                  const unsigned max_number) {
  std::string cacheFileName = "cache/random_numbers_" +
                              std::to_string(num_random_numbers) + "_" +
                              std::to_string(max_number) + ".dat";

  bool isNewDataGenerated = false;

  // Check if the cache file exists
  std::ifstream cacheFile(cacheFileName);
  if (!cacheFile.good()) {
    isNewDataGenerated = true;
  }

  // If data was not previously generated with the same parameters, generate new
  // data and store it
  if (isNewDataGenerated) {
    printf("No existing data found, generate data.\n");
    GenerateUniqueRandomNumbers(random_numbers, num_random_numbers, max_number);

    // Store the generated data in a file
    std::ofstream dataFile(cacheFileName, std::ios::out);
    for (unsigned i = 0; i < num_random_numbers; ++i) {
      dataFile << random_numbers[i] << "\n";
    }
    dataFile.close();
  } else {
    printf("Existing data found, reading data.\n");
    // Use the previously generated data from the cache file
    std::string line;
    unsigned count = 0;
    while (std::getline(cacheFile, line) && count < num_random_numbers) {
      unsigned num = (unsigned)std::stoll(line);
      random_numbers[count++] = num;
    }
  }
  // Close the cache file
  cacheFile.close();
}

void Shuffle(const unsigned num_random_numbers, unsigned *random_numbers) {
  // Fisher-Yates shuffle the unique numbers.
  for (unsigned index_1 = 0; index_1 < num_random_numbers; ++index_1) {
    unsigned num_left = num_random_numbers - index_1;
    unsigned index_2 = index_1 + (genrand_int32() % num_left);
    std::swap(random_numbers[index_1], random_numbers[index_2]);
  }
}

bool GenerateUniqueRandomNumbers(unsigned *random_numbers,
                                 const unsigned num_random_numbers,
                                 const unsigned max_number) {
  if (random_numbers == NULL) {
    return false;
  }

  // Generate a certain percentage extra of random numbers as a cushion.
  unsigned num_numbers = (unsigned)(num_random_numbers * 1.1);  //
  unsigned *temp_numbers = new unsigned[num_numbers];
  if (temp_numbers == NULL) {
    fprintf(stderr, "Failed to allocate space.\n");
    return false;
  }

  unsigned num_unique = 0;

  while (num_unique <
         num_random_numbers) {  
                                // num_random_numbers 个 unique keys.
    // Generate numbers.
    for (unsigned i = num_unique; i < num_numbers; ++i) {
      do {
        temp_numbers[i] = genrand_int32();
      } while (temp_numbers[i] >
               max_number);  // 生成 <= max_number 的数才会 break 出这个循环.
    }

    // Sort to put all copies of the same number next to each other.
    // TODO(dfalcantara): A faster sort would speed this up considerably, but I
    // don't want to introduce more dependencies.
    std::sort(temp_numbers, temp_numbers + num_numbers);

    // Determine which are unique & replace with new numbers.
    num_unique = 1;  // 注意这边 number of unique number 初始化为1, 而不是0
    for (unsigned i = 1; i < num_numbers; ++i) {
      if (temp_numbers[i - 1] == temp_numbers[i]) {
        temp_numbers[i - 1] = max_number;
      } else {
        num_unique++;
      }
    }

    // Move all of the non-unique numbers to the end.
    std::sort(temp_numbers, temp_numbers + num_numbers);
  }

  // Shuffle all of the unique keys. 
  Shuffle(num_unique, temp_numbers);

  // Copy the number of keys requested & toss the rest. 
  memcpy(random_numbers, temp_numbers, sizeof(unsigned) * num_random_numbers);
  delete[] temp_numbers;

  return true;
}

unsigned GenerateMultiples(const unsigned num_random_numbers,
                           float chance_of_repeating,
                           unsigned *random_numbers) {
  unsigned num_unique = 1;
  for (unsigned i = 1; i < num_random_numbers; ++i) {
    if (genrand_real1() < chance_of_repeating) {
      random_numbers[i] = random_numbers[i - 1];
    } else {
      num_unique++;
    }
  }
  printf("Unique keys: %u / %u\n", num_unique, num_random_numbers);
  return num_unique;
}

void GenerateQueries(const unsigned size, const float failure_rate,
                     unsigned *number_pool, unsigned *queries) {
  unsigned num_failed_queries = (unsigned)(failure_rate * size);
  unsigned num_good_queries = size - num_failed_queries;

  /// Pick some of the input keys as queries.
  if (num_good_queries) {
    Shuffle(size, number_pool);
    memcpy(queries, number_pool, sizeof(unsigned) * num_good_queries);
  }

  /// Pick some of the non-input keys as queries.
  if (num_failed_queries) {
    Shuffle(size, number_pool + size);
    memcpy(queries + num_good_queries, number_pool + size,
           sizeof(unsigned) * num_failed_queries);
  }

  /// Shuffle them all together.
  Shuffle(size, queries);
}

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
