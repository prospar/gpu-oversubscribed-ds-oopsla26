// Compilation command: g++ -std=c++17 \
 -O3 driver-tracegen.cpp -I. -o trace-gen -DVERIFY_TRACE -DPRINT_TRACE
// Generating the trace: ./trace-tester.out -ops=<totalOperations>
// -add=<percent> -rem=<percent> -dkp=<percent>  -npd=<percent> -nps=<percent>
// dkp: percentage of duplicate keys in each of the add, delete and search trace
// npd: percentage of keys that do not exist in the data structure in delete
// trace nps: percentage of keys that do not exist in the data structure in
// search trace

#include <algorithm>
#include <atomic>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <random>
#include <set>
#include <string>

using namespace std;
using std::atomic;
using std::cout;
using std::endl;
using std::string;
using std::to_string;
// using std::vector;
using std::filesystem::path;

uint64_t NUM_OPS = 1e8; // Total operations
uint32_t INSERT = 100;  // Percentage of insert
uint32_t DELETE = 0;    // Percentage of delete
uint32_t duplicateInAdd = 0;
uint32_t duplicateInRem = 0;
uint32_t duplicateInFind = 0;
uint32_t nonExistingDeleteKeysPercent = 0;
uint32_t nonExistingSearchKeysPercent = 0;
uint32_t tracePtr = 0;

static constexpr uint64_t RANDOM_SEED = 42;
static const string SL_TRACE_ROOT = "SL_TRACE_ROOT";

enum TRACE_PATTERN {
  SPARSE_UNIQUE = 0,
  SPARSE_REPEAT = 1,
  DENSE_UNIQUE = 2,
  DENSE_REPEAT = 3,
  PHASE_REPETITION = 4,
  MONOTONIC_INCREASE = 5,
  MONOTONIC_DECREASE = 6
};
enum OPERATION_TYPE { ADD_OP = 0, REM_OP = ADD_OP + 1, SEARCH_OP = REM_OP + 1 };

void validFlagsDescription();
int parse_args(char *);

uint32_t patternType(string);
string patternToString(uint32_t);

string constructTraceFilename(uint32_t, uint32_t, OPERATION_TYPE);

void generateTrace(uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t *,
                   uint32_t *, uint32_t *, uint32_t);

void create_file(path, uint32_t *, uint64_t);

path getProjectRoot() {
  string projectRootStr = getenv(SL_TRACE_ROOT.c_str());
  path projectRootPath = projectRootStr;
  return projectRootPath;
}

int main(int argc, char *argv[]) {
  for (int i = 1; i < argc; i++) {
    int error = parse_args(argv[i]);
    if (error == 1) {
      cerr << "Argument error, terminating run.\n";
      exit(EXIT_FAILURE);
    }
  }

  uint64_t ADD = NUM_OPS * (INSERT / 100.0);
  uint64_t REM = NUM_OPS * (DELETE / 100.0);
  uint64_t FIND = NUM_OPS - (ADD + REM);

  printf("NUM_OPS: %lu, ADD: %lu, REM: %lu, FIND: %lu DPA: %u DPR: %u DPF: %u "
         "NPD: %u NPS:%u trace pattern:%d\n",
         NUM_OPS, ADD, REM, FIND, duplicateInAdd, duplicateInRem,
         duplicateInFind, nonExistingDeleteKeysPercent,
         nonExistingSearchKeysPercent, tracePtr);

  uint32_t *addArr = (uint32_t *)malloc(sizeof(uint32_t) * ADD);
  uint32_t *remArr = (uint32_t *)malloc(sizeof(uint32_t) * REM);
  uint32_t *findArr = (uint32_t *)malloc(sizeof(uint32_t) * FIND);

  generateTrace(duplicateInAdd, duplicateInRem, duplicateInFind,
                nonExistingDeleteKeysPercent, nonExistingSearchKeysPercent,
                addArr, remArr, findArr, tracePtr);

  free(addArr);
  free(remArr);
  free(findArr);

  return EXIT_SUCCESS;
}
void validFlagsDescription() {
  cout << "ops: total number of operations\n"
       << "add: percentage of insert operations\n"
       << "rem: percentage of delete operations\n"
       << "dpa: percnetage of duplicate keys in the insertion array(0..100)\n"
       << "dpr: percnetage of duplicate keys in the delete array(0..100)\n"
       << "dpf: percnetage of duplicate keys in the search array(0..100)\n"
       << "npd: percentage of non existing keys in the deletion array(0..100)\n"
       << "nps: percentage of non existing keys in the search array(0..100)\n"
       << "tpt: pattern of trace: SPARSE_UNIQUE, SPARSE_REPEAT, DENSE_UNIQUE, "
          "DENSE_REPEAT, PHASE_REPETITION, MONOTONIC_INCREASE, "
          "MONOTONIC_DECREASE\n";
}

int parse_args(char *arg) {
  string s = string(arg);
  string s1;
  uint64_t val;

  try {
    s1 = s.substr(0, 4);
    string s2 = s.substr(5);
    if (s1 == "-tpt") {
      val = patternType(s2);
    } else
      val = stol(s2);
  } catch (...) {
    cout << "Supported: " << endl;
    cout << "-*=[], where * is:" << endl;
    validFlagsDescription();
    return 1;
  }

  if (s1 == "-ops") {
    NUM_OPS = val;
  } else if (s1 == "-add") {
    INSERT = val;
  } else if (s1 == "-rem") {
    DELETE = val;
  } else if (s1 == "-dpa") { // Percent of duplicate keys in insert trace
    duplicateInAdd = val;
  } else if (s1 == "-dpr") { // Percent of duplicate keys in remove trace
    duplicateInRem = val;
  } else if (s1 == "-dpf") { // Percent of duplicate keys in search trace
    duplicateInFind = val;
  } else if (s1 == "-npd") { // percent of non existing keys in delete queries
    nonExistingDeleteKeysPercent = val;
  } else if (s1 == "-nps") { // percent of non existing keys in search queries
    nonExistingSearchKeysPercent = val;
  } else if (s1 == "-tpt") {
    tracePtr = val;
  } else {
    cout << "Unsupported flag:" << s1 << "\n";
    cout << "Use the below list flags:\n";
    validFlagsDescription();
    return 1;
  }
  return 0;
}
string patternToString(uint32_t enumVal = 0) {
  string patternName = "-SPARSE_UNIQUE";
  if (enumVal == TRACE_PATTERN::SPARSE_UNIQUE)
    patternName = "-SPARSE_UNIQUE";
  else if (enumVal == TRACE_PATTERN::SPARSE_REPEAT)
    patternName = "-SPARSE_REPEAT";
  else if (enumVal == TRACE_PATTERN::DENSE_UNIQUE) {
    patternName = "-DENSE_UNIQUE";
  } else if (enumVal == TRACE_PATTERN::DENSE_REPEAT) {
    patternName = "-DENSE_REPEAT";
  } else if (enumVal == TRACE_PATTERN::PHASE_REPETITION) {
    patternName = "-PHASE_REPETITION";
  } else if (enumVal == TRACE_PATTERN::MONOTONIC_INCREASE) {
    patternName = "-MONOTONIC_INCREASE";
  } else if (enumVal == TRACE_PATTERN::MONOTONIC_DECREASE) {
    patternName = "-MONOTONIC_DECREASE";
  } else {
    cout << "Provide valid option for trace:SPARSE_UNIQUE, SPARSE_REPEAT, "
            "DENSE_UNIQUE, "
            "DENSE_REPEAT, PHASE_REPETITION, MONOTONIC_INCREASE, "
            "MONOTONIC_DECREASE\n";
    cout << "Terminating...\n";
    exit(0);
  }
  return patternName;
}

uint32_t patternType(string enumKey = "SPARSE_UNIQUE") {
  uint32_t valueP = 0;
  if (enumKey == "SPARSE_UNIQUE")
    valueP = TRACE_PATTERN::SPARSE_UNIQUE;
  else if (enumKey == "SPARSE_REPEAT")
    valueP = TRACE_PATTERN::SPARSE_REPEAT;
  else if (enumKey == "DENSE_UNIQUE") {
    valueP = TRACE_PATTERN::DENSE_UNIQUE;
  } else if (enumKey == "DENSE_REPEAT") {
    valueP = TRACE_PATTERN::DENSE_REPEAT;
  } else if (enumKey == "PHASE_REPETITION") {
    valueP = TRACE_PATTERN::PHASE_REPETITION;
  } else if (enumKey == "MONOTONIC_INCREASE") {
    valueP = TRACE_PATTERN::MONOTONIC_INCREASE;
  } else if (enumKey == "MONOTONIC_DECREASE") {
    valueP = TRACE_PATTERN::MONOTONIC_DECREASE;
  } else {
    cout << "Provide valid option for trace:SPARSE_UNIQUE, SPARSE_REPEAT, "
            "DENSE_UNIQUE, "
            "DENSE_REPEAT, PHASE_REPETITION, MONOTONIC_INCREASE, "
            "MONOTONIC_DECREASE\n";
    cout << "Terminating...\n";
    exit(0);
  }
  return valueP;
}

string constructTraceFilename(uint32_t dupKeyPercent,
                              uint32_t notPresentPercent, OPERATION_TYPE opr) {
  const string addtrace = "insert_trace-";
  const string remtrace = "delete_trace-";
  const string findtrace = "search_trace-";
  string dupKey = "-dup";
  string absentKey = "-absent";

  const uint32_t divisor_10e7 = 10000000;
  uint32_t doSearch = 100 - (INSERT + DELETE);
  assert(divisor_10e7 <= numeric_limits<uint32_t>::max());
  string oprStr = to_string(NUM_OPS / divisor_10e7) + "e7-";
  string oprPer = "";
  string strRep = "";
  string traceStepStr = to_string(TRACE_STEP / divisor_10e7) + "e7-";

  if (dupKeyPercent) {
    strRep = to_string(dupKeyPercent);
    dupKey = strRep + dupKey;
  } else {
    dupKey = "no" + dupKey;
  }

  if (notPresentPercent) {
    strRep = to_string(notPresentPercent);
    absentKey = "-" + strRep + absentKey;
  } else {
    absentKey = "-no" + absentKey;
  }

  string traceFile;

  path currPath = getProjectRoot();
  path filePathStr;
  switch (opr) {
  case ADD_OP:
    oprPer = to_string(INSERT) + "-add-" + to_string(DELETE) + "-rem-" +
             to_string(doSearch) + "-find-";
    traceFile = addtrace + traceStepStr + oprStr + oprPer + dupKey +
                patternToString(tracePtr) + ".bin";
    filePathStr = currPath / traceFile;
    break;
  case REM_OP:
    if (DELETE) {
      oprPer = to_string(INSERT) + "-add-" + to_string(DELETE) + "-rem-" +
               to_string(doSearch) + "-find-";
      traceFile = remtrace + traceStepStr + oprStr + oprPer + dupKey +
                  absentKey + patternToString(tracePtr) + ".bin";
      filePathStr = currPath / traceFile;
    }
    break;
  case SEARCH_OP:
    if (doSearch) {
      oprPer = to_string(INSERT) + "-add-" + to_string(DELETE) + "-rem-" +
               to_string(doSearch) + "-find-";
      traceFile = findtrace + traceStepStr + oprStr + oprPer + dupKey +
                  absentKey + patternToString(tracePtr) + ".bin";
      filePathStr = currPath / traceFile;
    }
    break;
  default:
    bool invalidOperationType = false;
    assert(invalidOperationType);
    break;
  }
  return filePathStr;
}
void create_file(path pth, uint32_t *data, uint64_t size) {
  FILE *fptr = fopen(pth.string().c_str(), "wb+");
  // return total object written to file
  uint64_t totalEle = fwrite(data, sizeof(uint32_t), size, fptr);
  assert(totalEle == size);
  fclose(fptr);
}

void generateTrace(uint32_t dupAdd, uint32_t dupRem, uint32_t dupFind,
                   uint32_t notPresentInDelete, uint32_t notPresentInSearch,
                   uint32_t *addArr, uint32_t *delArr, uint32_t *searchArr,
                   uint32_t tracePattern) {

  // configure random number generator
  std::mt19937 mt(0);                      // for insertion list
  std::mt19937 mt_value(RANDOM_SEED >> 1); // for generating values
  std::mt19937 mt_delete(RANDOM_SEED);     // for delete sequence
  std::mt19937 mt_find(RANDOM_SEED << 3);  // for find sequence
  // for shuffle of the insertion vector
  std::mt19937 mt_shuffle(175788329);
  uint64_t addOp = (INSERT / 100.0) * NUM_OPS;
  uint64_t remOp = (DELETE / 100.0) * NUM_OPS;
  uint64_t searchOp = NUM_OPS - (addOp + remOp);
  // delete queries should be less than the total insert
  assert(remOp <= addOp);
  // TODO: change the assert if searches > 60% of total operations
  // and total unique keys in search > 3.0*10^9
  assert(dupAdd <= 80);
  assert(dupRem <= 80);
  assert(dupFind <= 80);
  if (tracePattern == TRACE_PATTERN::DENSE_REPEAT ||
      tracePattern == TRACE_PATTERN::SPARSE_REPEAT) {
    assert(dupAdd);
    if (remOp)
      assert(dupRem);
    if (searchOp)
      assert(dupFind);
  }
  uint64_t dupInAdd = addOp * (dupAdd / 100.0);
  uint64_t nonExistingKeysDelete = remOp * (notPresentInDelete / 100.0);
  uint64_t nonExistingKeysSearch = searchOp * (notPresentInSearch / 100.0);

  // boolean array to track the duplicate and key occurence
  std::vector<bool> uniqueTracker(UINT32_MAX, false);
  std::vector<bool> uniqueDeleteTracker(UINT32_MAX, false);
  std::vector<bool> uniqueSearchTracker(UINT32_MAX, false);

  uint32_t uniqueKeysTrace = addOp - dupInAdd;
  cout << "Progress ADD trace uniqueKeys:" << uniqueKeysTrace
       << "Duplicate:" << dupInAdd << "\n";

  uint64_t i = 0;
  uint32_t temp = 0;
  uint64_t uniKeyIndex = uniqueKeysTrace;
  // Generate keys for add
  std::uniform_int_distribution<uint32_t> distribution(1, UINT32_MAX - 1);
  vector<uint32_t> addKeys;
  addKeys.reserve(addOp);
  uint64_t stepDup = TRACE_STEP * (dupAdd / 100.0);
  uint64_t stepUnique = TRACE_STEP - stepDup;
  uint32_t totalIter = addOp / TRACE_STEP;
  cout << "In each batch: " << stepUnique << " Duplicate: " << stepDup << "\n";

  if ((tracePattern == TRACE_PATTERN::SPARSE_UNIQUE) ||
      (tracePattern == TRACE_PATTERN::SPARSE_REPEAT)) {
    cout << "Generating sparse trace\n";
    i = 0;
    uint32_t z = 0;
    while (z < totalIter) {
      vector<uint32_t> tempKeys;
      tempKeys.reserve(TRACE_STEP);
      uint64_t u = 0;
      std::vector<bool> trackerStep(UINT32_MAX, false);
      while (u < stepUnique) {
        temp = distribution(mt);
        if (!uniqueTracker[temp]) {
          uniqueTracker[temp] = true;
          trackerStep[temp] = true;
          tempKeys.push_back(temp);
          u++;
        }
      }
      uint64_t j = 0;
      while (u < TRACE_STEP) {
        if (trackerStep[j]) {
          tempKeys.push_back(j);
          u++;
        }
        j++;
      }
      std::srand(std::time(0));
      std::random_device rd;
      std::mt19937 g(rd());
      std::shuffle(tempKeys.begin(), tempKeys.end(), g);
      addKeys.insert(addKeys.begin() + (TRACE_STEP * z), tempKeys.begin(),
                     tempKeys.end());
      z++;
    }
  } else if (tracePattern == TRACE_PATTERN::PHASE_REPETITION) {
    // TODO: implement the phase behaviour
  } else {
    cout << "Generating dense trace\n";
    i = 0;
    uint32_t z = 0;
    while (z < totalIter) {
      vector<uint32_t> tempKeys;
      tempKeys.reserve(TRACE_STEP);
      uint64_t u = 0;
      while (u < stepUnique) {
        temp = i + 1;
        uniqueTracker[temp] = true;
        tempKeys.push_back(temp);
        i++;
        u++;
      }
      uint32_t j = 1 + (TRACE_STEP * z);
      while (u < TRACE_STEP) {
        tempKeys.push_back(j++);
        u++;
      }

      if ((tracePattern == TRACE_PATTERN::DENSE_UNIQUE) ||
          (tracePattern == TRACE_PATTERN::DENSE_REPEAT))
        std::shuffle(tempKeys.begin(), tempKeys.end(), mt_shuffle);
      addKeys.insert(addKeys.begin() + (TRACE_STEP * z), tempKeys.begin(),
                     tempKeys.end());
      z++;
    }

    if (tracePattern == TRACE_PATTERN::MONOTONIC_DECREASE) {
      reverse(addKeys.begin(), addKeys.end());
    }
  }
  // copy the keys to insert array
  copy(addKeys.begin(), addKeys.end(), addArr);

  cout << "Insert trace generated\n";
  // Allowing printing trace to console only for 1000 keys
  if (addOp < 1000) {
#if defined(PRINT_TRACE)
    cout << "Content of the insertion array:\n";
    int prInd = 0;
    while (prInd < addOp) {
      cout << addArr[prInd++] << " ";
    }
    cout << "\n";
#endif // PRINT_INSERT_TRACE
  }

  // Write trace to file
  path fileName = constructTraceFilename(dupAdd, 0, ADD_OP);
  create_file(fileName, addArr, addOp);
  cout << "File for insert trace: " << fileName << "generated.\n";

  uint64_t dupInExistingKeys, dupInNonExistingKeys, uniqueNonExistingKeys;

  // trace for DELETE keys
  if (remOp) {
    uint64_t dupInDel = remOp * (dupRem / 100.0);
    cout << "Total Remove: " << remOp << " Unique Keys: " << (remOp - dupInDel)
         << " Dup Keys: " << dupInDel << "\n";
    std::vector<uint32_t> deleteVector;
    deleteVector.reserve(remOp);

    stepDup = TRACE_STEP * (dupRem / 100.0);
    stepUnique = TRACE_STEP - stepDup;
    uint64_t stepNonExistingKeys = TRACE_STEP * (dupRem / 100.0);
    uint64_t stepExistingKeys = TRACE_STEP - stepNonExistingKeys;

    // Assume total operation is a multiple of trace step
    totalIter = remOp / TRACE_STEP;
    cout << "In Del batch Unique:" << stepUnique << " Not present: " << stepDup
         << "\n";
    if ((tracePattern == TRACE_PATTERN::SPARSE_UNIQUE) ||
        (tracePattern == TRACE_PATTERN::SPARSE_REPEAT)) {
      cout << "Generating sparse trace for delete\n";
      i = 0;
      uint32_t z = 0;
      while (z < totalIter) {
        vector<uint32_t> tempKeys;
        tempKeys.reserve(TRACE_STEP);
        uint64_t u = 0;
        std::vector<bool> trackerStep(UINT32_MAX, false);
        uint64_t trackExisting = 0;
        uint64_t trackNonexisting = 0;
        while (u < TRACE_STEP) {
          // use different distribution for search keys to avoid same sequence
          // as add
          temp = distribution(mt_delete);
          // key present in hashtable
          if (uniqueTracker[temp] && !uniqueDeleteTracker[temp] &&
              (trackExisting < stepExistingKeys)) {
            uniqueDeleteTracker[temp] = true;
            trackerStep[temp] = true;
            tempKeys.push_back(temp);
            u++;
            trackExisting++;
          } else if (uniqueDeleteTracker[temp] &&
                     (trackNonexisting < stepNonExistingKeys)) {
            uniqueDeleteTracker[temp] = true;
            tempKeys.push_back(temp);
            trackerStep[temp] = true;
            u++;
            trackNonexisting++;
          } else if (!uniqueTracker[temp] &&
                     (trackNonexisting < stepNonExistingKeys)) {
            // keys not in hashtable
            uniqueDeleteTracker[temp] = true;
            tempKeys.push_back(temp);
            trackerStep[temp] = true;
            u++;
            trackNonexisting++;
          }
        }
        assert((trackExisting + trackNonexisting) == TRACE_STEP);

        std::srand(std::time(0));
        std::random_device rd;
        std::mt19937 g(rd());
        std::shuffle(tempKeys.begin(), tempKeys.end(), g);
        deleteVector.insert(deleteVector.begin() + (TRACE_STEP * z),
                            tempKeys.begin(), tempKeys.end());
        z++;
        cout << "Delete trace iteration: " << z << " completed\n";
      }
    } else if (tracePattern == TRACE_PATTERN::PHASE_REPETITION) {
      // TODO: for larger trace the trace pattern covered by
      // dense repeat and dense unique
    } else {
      cout << "Generating dense trace for delete\n";
      i = 1;
      uint32_t z = 0;

      while (z < totalIter) {
        vector<uint32_t> tempKeys;
        tempKeys.reserve(TRACE_STEP);
        uint64_t u = 0;
        // std::vector<bool> trackerStep(UINT32_MAX, false);
        uint64_t trackExisting = 0;
        uint64_t trackNonexisting = 0;
        // key present in hashtable
        while (u < stepExistingKeys) {
          temp = i;
          if (uniqueTracker[temp] && !uniqueDeleteTracker[temp]) {
            uniqueDeleteTracker[temp] = true;
            // trackerStep[temp] = true;
            tempKeys.push_back(temp);
            trackExisting++;
            i++;
            u++;
          }
        }
        uint32_t j = 1 + (TRACE_STEP * z);
        // key not in hashtable
        while (u < TRACE_STEP) {
          if (uniqueDeleteTracker[j] || !uniqueTracker[j]) {
            tempKeys.push_back(j++);
            trackNonexisting++;
            u++;
          }
        }
        assert((trackExisting + trackNonexisting) == TRACE_STEP);

        std::srand(std::time(0));
        std::random_device rd;
        std::mt19937 g(rd());
        std::shuffle(tempKeys.begin(), tempKeys.end(), g);
        if ((tracePattern == TRACE_PATTERN::DENSE_UNIQUE) ||
            (tracePattern == TRACE_PATTERN::DENSE_REPEAT))
          std::shuffle(tempKeys.begin(), tempKeys.end(), mt_shuffle);

        deleteVector.insert(deleteVector.begin() + (TRACE_STEP * z),
                            tempKeys.begin(), tempKeys.end());
        z++;
        cout << "Delete trace iteration: " << z << " completed\n";
      }
    }
    cout << "Progress::: Delete keys generated\n";
    // copy to the delete array
    copy(deleteVector.begin(), deleteVector.end(), delArr);

    // Write trace to file
    fileName = constructTraceFilename(dupRem, notPresentInDelete, REM_OP);
    create_file(fileName, delArr, remOp);
    cout << "File for delete trace: " << fileName << "generated.\n";

    if (remOp < 1000) {
#if defined(PRINT_TRACE)
      cout << "Content of the delete array:\n";
      uint32_t prInd = 0;
      while (prInd < remOp) {
        cout << delArr[prInd++] << " ";
      }
      cout << "\n";
#endif // PRINT_INSERT_TRACE
    }
  }

  // trace of search keys
  if (searchOp) {
    uint64_t dupInSearch = searchOp * (dupFind / 100.0);
    cout << "Total search: " << searchOp
         << " Unique Keys: " << (searchOp - dupInSearch)
         << " Dup Keys: " << dupInSearch << "\n";
    std::vector<uint32_t> searchVector;
    searchVector.reserve(searchOp);

    stepDup = TRACE_STEP * (dupFind / 100.0);
    stepUnique = TRACE_STEP - stepDup;
    uint64_t stepNonExistingKeys = TRACE_STEP * (notPresentInSearch / 100.0);
    uint64_t stepExistingKeys = TRACE_STEP - stepNonExistingKeys;
    uint64_t stepExistingDup = stepExistingKeys * (dupFind / 100.0);
    uint64_t stepExistingUnique = stepExistingKeys - stepExistingUnique;
    uint64_t stepNonExistingDup = stepNonExistingKeys * (dupFind / 100.0);
    uint64_t stepNonExistingUnique = stepNonExistingKeys - stepNonExistingDup;

    // Assume total operation is a multiple of trace step
    totalIter = searchOp / TRACE_STEP;
    cout << "In Search batch Uniques:" << stepUnique
         << " Duplicates: " << stepDup << " Existing keys: " << stepExistingKeys
         << " Non existing keys : " << stepNonExistingKeys << "\n";
    if ((tracePattern == TRACE_PATTERN::SPARSE_UNIQUE) ||
        (tracePattern == TRACE_PATTERN::SPARSE_REPEAT)) {
      cout << "generating sparse trace for search\n";
      i = 0;
      uint32_t z = 0;
      while (z < totalIter) {
        vector<uint32_t> tempKeys;
        tempKeys.reserve(TRACE_STEP);
        uint64_t u = 0;
        uint64_t trackExistingUnique = 0;
        uint64_t trackNonexistingUnique = 0;
        uint64_t trackExistingDup = 0;
        uint64_t trackNonexistingDup = 0;
        while (u < stepUnique) {
          // use different distribution for search keys to avoid same sequence
          // as add
          temp = distribution(mt_find);
          // key present in hashtable
          if (uniqueTracker[temp] && !uniqueDeleteTracker[temp] &&
              (trackExistingUnique < stepExistingUnique) &&
              !uniqueSearchTracker[temp]) {
            uniqueSearchTracker[temp] = true;
            tempKeys.push_back(temp);
            u++;
            trackExistingUnique++;
          } else if (uniqueDeleteTracker[temp] &&
                     (trackNonexistingUnique < stepNonExistingUnique)) {
            uniqueSearchTracker[temp] = true;
            tempKeys.push_back(temp);
            u++;
            trackNonexistingUnique++;
          } else if (!uniqueTracker[temp] &&
                     (trackNonexistingUnique < stepNonExistingUnique)) {
            // keys not in hashtable
            uniqueSearchTracker[temp] = true;
            tempKeys.push_back(temp);
            u++;
            trackNonexistingUnique++;
          }
        }
        assert((trackExistingUnique + trackNonexistingUnique) == stepUnique);
        while (u < TRACE_STEP) {
          temp = distribution(mt);
          if (uniqueTracker[temp] && uniqueSearchTracker[temp] &&
              !uniqueDeleteTracker[temp] &&
              (trackExistingDup < stepExistingDup)) {
            tempKeys.push_back(temp);
            trackExistingDup++;
            u++;
          } else if (uniqueSearchTracker[temp] && uniqueDeleteTracker[temp] &&
                     (trackNonexistingDup < stepNonExistingDup)) {
            tempKeys.push_back(temp);
            trackNonexistingDup++;
            u++;
          } else if (uniqueSearchTracker[temp] && !uniqueTracker[temp] &&
                     (trackNonexistingDup < stepNonExistingDup)) {
            tempKeys.push_back(temp);
            trackNonexistingDup++;
            u++;
          }
        }
        std::srand(std::time(0));
        std::random_device rd;
        std::mt19937 g(rd());
        std::shuffle(tempKeys.begin(), tempKeys.end(), g);
        searchVector.insert(searchVector.begin() + (TRACE_STEP * z),
                            tempKeys.begin(), tempKeys.end());
        z++;
        cout << "Search trace iteration: " << z << " completed\n";
      }
    } else if (tracePattern == TRACE_PATTERN::PHASE_REPETITION) {
      // TODO: for larger trace the trace pattern covered by
      // dense repeat and dense unique
    } else {
      cout << "Generating dense trace for search\n";
      i = 1;
      uint32_t z = 0;

      while (z < totalIter) {
        vector<uint32_t> tempKeys;
        tempKeys.reserve(TRACE_STEP);
        uint64_t u = 0;
        std::vector<bool> trackerStep(UINT32_MAX, false);
        uint64_t trackExistingUnique = 0;
        uint64_t trackNonexistingUnique = 0;
        uint64_t trackExistingDup = 0;
        uint64_t trackNonexistingDup = 0;
        // key present in hashtable
        while (u < stepUnique) {
          temp = i;
          if (uniqueTracker[temp] && !uniqueDeleteTracker[temp] &&
              (trackExistingUnique < stepExistingUnique)) {
            uniqueSearchTracker[temp] = true;
            tempKeys.push_back(temp);
            trackExistingUnique++;
            u++;
          } else if (uniqueTracker[temp] && uniqueDeleteTracker[temp] &&
                     (trackNonexistingUnique < stepNonExistingUnique)) {
            uniqueSearchTracker[temp] = true;
            tempKeys.push_back(temp);
            trackNonexistingUnique++;
            u++;
          } else if (!uniqueTracker[temp] &&
                     (trackNonexistingUnique < stepNonExistingUnique)) {
            uniqueSearchTracker[temp] = true;
            tempKeys.push_back(temp);
            trackNonexistingUnique++;
            u++;
          }
          i++;
        }
        assert((trackNonexistingUnique + trackExistingUnique) == stepUnique);
        uint32_t j = 1 + (TRACE_STEP * z);
        // key not in hashtable
        while (u < TRACE_STEP) {
          cout << j << " ";
          if (uniqueSearchTracker[j] && uniqueTracker[j] &&
              !uniqueDeleteTracker[j] && (trackExistingDup < stepExistingDup)) {
            tempKeys.push_back(j);
            trackExistingDup++;
            u++;
          } else if (uniqueSearchTracker[j] && !uniqueTracker[j] &&
                     (trackNonexistingDup < stepNonExistingDup)) {
            tempKeys.push_back(j);
            trackNonexistingDup++;
            u++;
          } else if (uniqueTracker[j] && uniqueDeleteTracker[j] &&
                     uniqueSearchTracker[j] &&
                     (trackNonexistingDup < stepNonExistingDup)) {
            tempKeys.push_back(j);
            trackNonexistingDup++;
            u++;
          }
          j++;
        }
        assert((trackExistingDup + trackNonexistingDup) == stepDup);

        std::srand(std::time(0));
        std::random_device rd;
        std::mt19937 g(rd());
        // std::shuffle(tempKeys.begin(), tempKeys.end(), g);
        if ((tracePattern == TRACE_PATTERN::DENSE_UNIQUE) ||
            (tracePattern == TRACE_PATTERN::DENSE_REPEAT))
          std::shuffle(tempKeys.begin(), tempKeys.end(), mt_shuffle);

        searchVector.insert(searchVector.begin() + (TRACE_STEP * z),
                            tempKeys.begin(), tempKeys.end());
        z++;
        cout << "Search trace iteration: " << z << " completed\n";
      }
    }

    cout << "Progress::: Search keys generated\n";

    // std::shuffle(searchVector.begin(), searchVector.end(), mt_shuffle);

    copy(searchVector.begin(), searchVector.end(), searchArr);
    // Write trace to file
    fileName = constructTraceFilename(dupFind, notPresentInSearch, SEARCH_OP);
    create_file(fileName, searchArr, searchOp);
    cout << "File for search trace: " << fileName << "generated.\n";
    if (searchOp < 1000) {
#if defined(PRINT_TRACE)
      cout << "Content of the search array:\n";
      uint32_t prInd = 0;
      while (prInd < searchOp) {
        cout << searchArr[prInd++] << " ";
      }
      cout << "\n";

#endif // PRINT_INSERT_TRACE
    }
  }
}
