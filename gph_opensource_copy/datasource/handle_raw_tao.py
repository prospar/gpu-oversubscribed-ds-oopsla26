import hashlib
from collections import defaultdict
import random

OUTPUT_KEY_FILE = 'tao_key_encoded.txt'
OUTPUT_VALUE_FILE = 'tao_value_encoded.txt'


apprears = set()

def complement_array(array, n):
    while len(array) < n:
        array.append(random.choice(array))
def generate_negative_query(n):
    negative_queries = []
    while len(negative_queries) < n:
        q = random.randint(1, 2**32 - 2)
        if q not in apprears:
            negative_queries.append(q)
    return negative_queries

def process_tao():
    print("start process tao graph")
    with open("tao_raw_graph_id1.txt", 'r+', encoding="utf-8") as graphf1,open("tao_raw_graph_id2.txt", 'r+', encoding="utf-8") as graphf2, open(OUTPUT_KEY_FILE, 'w') as f_key, open(OUTPUT_VALUE_FILE, 'w') as f_value:
        while True:
            graph_id1 = graphf1.readline().strip()
            graph_id2 = graphf2.readline().strip()
            if graph_id1:
                hash_object = hashlib.sha256("{}|{}".format(graph_id1,graph_id2).encode())
                hash_digest = hash_object.digest()
                edge_hash32 = int.from_bytes(hash_digest[-4:], byteorder='little', signed=False)
                if edge_hash32 in apprears:
                    continue
                else:
                    apprears.add(edge_hash32)
                f_key.write("{}\n".format(edge_hash32))
                f_value.write("{}\n".format(random.randint(1, 2**32 - 2)))
            else:
                break
    print("process tao graph complete, with {} edges".format(len(apprears)))

    total_query_num = 200000000
    positive_queries = []
    
    print("start process tao queries")
    with open("tao_raw_queries_id1.txt", "r+", encoding="utf-8") as qf1, open("tao_raw_queries_id2.txt", "r+", encoding="utf-8") as qf2:
        while True:
            q1 = qf1.readline().strip()
            q2 = qf2.readline().strip()
            if q1:
                hash_object = hashlib.sha256("{}|{}".format(q1,q2).encode())
                hash_digest = hash_object.digest()
                edge_hash32 = int.from_bytes(hash_digest[-4:], byteorder='little', signed=False)
                if edge_hash32 in apprears:
                    positive_queries.append(edge_hash32)
            else:
                break
        print("{} positive queries found".format(len(positive_queries)))
    print("Make complement on queries")
    complement_array(positive_queries, total_query_num)
    
    print("Shuffling queries")
    random.shuffle(positive_queries)

    print("generating negative queries")
    negative_queires = generate_negative_query(total_query_num)

    for pos_ratio in [0,25,50,75,100]:
        output_file_name = "tao_workload_pos{}_size{}.txt".format(pos_ratio, total_query_num)
        print("Make {}...".format(output_file_name))
        pos_num = int(total_query_num * (pos_ratio * 0.01))
        neg_num = total_query_num - pos_num
        queries = []
        queries.extend(positive_queries[0:pos_num])
        queries.extend(negative_queires[0:neg_num])
        print("Shuffling...".format(output_file_name))
        random.shuffle(queries)
        print("Writing to {}...".format(output_file_name))
        with open(output_file_name, 'w') as file:
            for q in queries:
                file.write("{}\n".format(q))


process_tao()