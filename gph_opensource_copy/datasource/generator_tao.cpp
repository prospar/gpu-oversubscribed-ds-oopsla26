#include <limits.h>  // INT_MAX
#include <stdint.h>

#include <cassert>
#include <chrono>
#include <iostream>
#include <random>
#include <unordered_map>
#include <vector>
#include <fstream>
#include <string>

#include "timer.h"
int64_t CurrentTimeNanos() {
  std::chrono::time_point<std::chrono::system_clock> now = std::chrono::system_clock::now();
  return std::chrono::duration_cast<std::chrono::nanoseconds>(now.time_since_epoch()).count();
}

namespace {
// // size of primary_shards_weights = 50
const std::vector<double> primary_shards_weights{
    // from read_only.json in https://github.com/audreyccheng/taobench.git
    94036, 36224, 3600, 612, 612, 612, 612, 612, 614, 612, 612, 612, 612,
    612,   612,   612,  614, 612, 612, 612, 612, 612, 612, 612, 612, 614,
    612,   612,   612,  612, 612, 612, 612, 614, 612, 612, 612, 612, 612,
    612,   612,   614,  612, 612, 612, 612, 612, 612, 612, 600};
const std::vector<double> remote_shards_weights{
    // from read_only.json in https://github.com/audreyccheng/taobench.git
    31712, 2563, 1925, 1722, 1663, 1620, 1037, 679, 381, 247, 176, 149, 130,
    119,   112,  99,   96,   89,   80,   80,   76,  64,  64,  64,  64,  48,
    48,    48,   48,   48,   45,   32,   32,   32,  32,  32,  32,  32,  32,
    17,    16,   16,   16,   16,   16,   16,   16,  16,  16,  15};
const std::vector<double> edge_types_weights{
    52, 200, 20, 728};  // from read_only.json in
                        // https://github.com/audreyccheng/taobench.git
}  // namespace

namespace rnd {
static std::mt19937 gen(std::random_device{}());
}
namespace counter {
thread_local static uint32_t key_count(
    std::uniform_int_distribution<>(0)(rnd::gen));
}

namespace TAOBench {
enum class EdgeType { Unique, Bidirectional, UniqueAndBidirectional, Other };

struct Association {
  Association(int64_t p_key, int64_t r_key) : id1(p_key), id2(r_key) {}
  Association() {}
  int64_t id1;
  int64_t id2;
};

namespace utils {
// returns number of nanoseconds since epoch

template <typename R, typename P = std::ratio<1>>
class Timer {
 public:
  void Start() { time_ = Clock::now(); }

  R End() {
    Duration span;
    Clock::time_point t = Clock::now();
    span = std::chrono::duration_cast<Duration>(t - time_);
    return span.count();
  }

  R GetStartTime() {
    Duration span =
        std::chrono::duration_cast<Duration>(time_.time_since_epoch());
    return span.count();
  }

 private:
  using Duration = std::chrono::duration<R, P>;
  using Clock = std::chrono::high_resolution_clock;

  Clock::time_point time_;
};
}  // namespace utils
}  // namespace TAOBench

class GenEdge {
 public:
  struct Field {
    Field(std::string const &name_, int64_t value_)
        : name(name_), value(value_) {}
    std::string name;
    int64_t value;
  };

  struct Graph {
    Graph(std::vector<Field> const &k) : key(k) {}
    std::vector<Field> key;  // 1 int for objects, 3 (id1, id2, type) for edge
  };
  struct Edge {
    Edge(int64_t p_key, int64_t r_key, TAOBench::EdgeType t)
        : primary_key(p_key), remote_key(r_key), type(t) {}
    Edge() {}
    int64_t primary_key;
    int64_t remote_key;
    TAOBench::EdgeType type;
  };

  using key_t = uint32_t;

  static constexpr int NUM_SHARDS = 50;          // default shareds in TAOBench
  static constexpr int num_threads = 1;          // one thread for one db
  static constexpr long total_keys = 165000000;  // default n in TAOBench

  std::discrete_distribution<> primary_shards_distribution;
  std::discrete_distribution<> remote_shards_distribution;
  std::discrete_distribution<> edge_types_distribution;
  std::vector<std::string> edge_types;

  std::unordered_map<int, std::vector<Edge>> shard_to_edges;

  GenEdge() {
    primary_shards_distribution = std::discrete_distribution<>(
        primary_shards_weights.begin(), primary_shards_weights.end());
    remote_shards_distribution = std::discrete_distribution<>(
        remote_shards_weights.begin(), remote_shards_weights.end());
    edge_types_distribution = std::discrete_distribution<>(
        edge_types_weights.begin(), edge_types_weights.end());
    edge_types = {"unique", "bidirectional", "unique_and_bidirectional",
                  "other"};

    long num_keys_per_thread = total_keys / num_threads;
    BatchInsertThread(0 >= total_keys % num_threads ? num_keys_per_thread
                                                    : num_keys_per_thread + 1);
    long sum = 0;
    for (auto const &[fi, se] : shard_to_edges) {
      sum += se.size();
    }
    assert(sum == total_keys);
  }

  void getAllEdges(int64_t *edge_id1, int64_t *edge_id2, size_t n) {
    assert(n == this->total_keys);
    size_t cnt = 0;
    for (auto const &[fi, se] : shard_to_edges) {
      for (Edge e: se) {
        edge_id1[cnt] = e.primary_key;
        edge_id2[cnt] = e.remote_key;
        cnt += 1;
      }
    }
  }

  // Function run on each thread for batch inserts.
  int BatchInsertThread(long num_ops) {
    for (long i = 0; i < num_ops; ++i) {
      LoadRow();
    }
  }

  // This function is used in the batch insert phase to generate an edge with
  // new primary and remote keys.
  void LoadRow() {
    std::uniform_int_distribution<> unif(0, NUM_SHARDS - 1);
    int primary_shard =
        unif(rnd::gen);  // distribute keys evenly into [0,49] shards
    int remote_shard = remote_shards_distribution(rnd::gen);
    int64_t primary_key = GenerateKey(primary_shard);
    int64_t remote_key = GenerateKey(remote_shard);
    TAOBench::EdgeType edge_type = GetRandomEdgeType();
    WriteToBuffers(primary_shard, primary_key, remote_key, edge_type);
  }

  TAOBench::EdgeType GetRandomEdgeType() {
    return EdgeStringToType(edge_types[edge_types_distribution(rnd::gen)]);
  }

  inline TAOBench::EdgeType EdgeStringToType(std::string const &edge_type) {
    if (edge_type == "unique") {
      return TAOBench::EdgeType ::Unique;
    } else if (edge_type == "bidirectional") {
      return TAOBench::EdgeType ::Bidirectional;
    } else if (edge_type == "unique_and_bidirectional") {
      return TAOBench::EdgeType ::UniqueAndBidirectional;
    } else {
      return TAOBench::EdgeType ::Other;
    }
  }

  int64_t GenerateKey(int shard) {
    int64_t timestamp = CurrentTimeNanos();
    int64_t seqnum = counter::key_count++;
    // 64 bit int split into 7 bit shard, 17 thread-specific sequence number,
    // and bottom 40 bits of timestamp
    // this design is fairly arbitrary; intent is just to minimize duplicate
    // keys across threads
    return (((int64_t)shard) << 57) + ((seqnum & 0x1FFFF) << 40) +
           (timestamp & 0xFFFFFFFFFF);
  }

  void WriteToBuffers(int primary_shard, int64_t primary_key,
                      int64_t remote_key, TAOBench::EdgeType edge_type) {
    int failed_ops = 0;
    Edge tmp{primary_key, remote_key, edge_type};
    shard_to_edges[primary_shard].emplace_back(tmp);
  }

  // Given a shard, this function will return a "fake key" that is smaller than
  // every real key on the shard, but larger than any key on the previous shard.
  int64_t GetShardStartKey(int shard) {
    if (shard < 0 || shard >= NUM_SHARDS) {
      throw std::runtime_error(
          "Invalid spreader passed to GetSpreaderPseudoStartKey");
    }
    return ((int64_t)shard) << 57;
  }

  // Given a shard, this function wil return a "fake key" that is larger than
  // every real key on the shard, but smaller than any key on the next shard.
  int64_t GetShardEndKey(int shard) {
    if (shard < 0 || shard >= NUM_SHARDS) {
      throw std::runtime_error(
          "Invalid spreader passed to GetSpreaderPseudoEndKey");
    }
    return ((int64_t)(shard + 1)) << 57;
  }

  Edge const &GetRandomEdge() {
    auto it = shard_to_edges.find(primary_shards_distribution(rnd::gen));

    while (it == shard_to_edges.end()) {
      it = shard_to_edges.find(primary_shards_distribution(rnd::gen));
    }

    std::uniform_int_distribution<int> edge_selector(0,
                                                     (it->second).size() - 1);
    return (it->second)[edge_selector(rnd::gen)];
  }

  Graph get_single_item(bool is_edge) {
    Edge const &edge = GetRandomEdge();
    if (is_edge) {
      return {{{"id1", edge.primary_key},
               {"id2", edge.remote_key},
               {"type", static_cast<int64_t>(edge.type)}}};
    } else {
      return {{{"id", edge.primary_key}}};
    }
  }

  void get_query_objects(int64_t *obj_id_array, int num) {
    for (int i = 0; i < num; i++) {
      obj_id_array[i] = get_single_item(false).key[0].value;
    }
  }
  
  void get_query_edges(int64_t *id1_array, int64_t *id2_array, int num) {
    std::vector<Field> tmp;
    for (int i = 0; i < num; i++) {
      tmp = get_single_item(true).key;
      id1_array[i] = tmp[0].value;
      id2_array[i] = tmp[1].value;
    }
  }
};

void writeToFile(std::string filePath, int64_t* array, size_t n) {
    std::ofstream outputFile(filePath);
    if (outputFile.is_open()) {
        for (size_t i = 0; i < n; ++i) {
            outputFile << array[i] << std::endl;
        }
        
        outputFile.close();
        std::cout << "Array successfully written to file." << std::endl;
    } else {
        std::cerr << "Error opening the file." << std::endl;
    }
}

int main() {
  GenEdge generator;
  size_t queries_n = 200000000;
  int64_t* id1_assoc_queries = new int64_t[queries_n];
  int64_t* id2_assoc_queries = new int64_t[queries_n];

  generator.get_query_edges(id1_assoc_queries, id2_assoc_queries, queries_n);

  int64_t* id1_graph = new int64_t[generator.total_keys];
  int64_t* id2_graph = new int64_t[generator.total_keys];

  generator.getAllEdges(id1_graph, id2_graph, generator.total_keys);

  writeToFile("tao_raw_queries_id1.txt", id1_assoc_queries, queries_n);
  writeToFile("tao_raw_queries_id2.txt", id2_assoc_queries, queries_n);
  writeToFile("tao_raw_graph_id1.txt", id1_graph, generator.total_keys);
  writeToFile("tao_raw_graph_id2.txt", id2_graph, generator.total_keys);

  delete [] id1_assoc_queries;
  delete [] id2_assoc_queries;
  delete [] id1_graph;
  delete [] id2_graph;
  return 0;
}