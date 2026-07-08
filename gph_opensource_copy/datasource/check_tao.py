import hashlib
from collections import defaultdict
import random


apprears = set()
def process_tao():
    print("start process tao graph")
    with open("tao_raw_graph_id1.txt", 'r+', encoding="utf-8") as graphf1,open("tao_raw_graph_id2.txt", 'r+', encoding="utf-8") as graphf2:
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
            else:
                break
    print("process tao graph complete")

    cnt = 0
    pos_cnt = 0
    with open("tao_raw_queries_id1.txt", 'r+', encoding="utf-8") as qf1,open("tao_raw_queries_id2.txt", 'r+', encoding="utf-8") as qf2:
        while True:
            q1 = qf1.readline().strip()
            q2 = qf2.readline().strip()
            if q1:
                hash_object = hashlib.sha256("{}|{}".format(q1,q2).encode())
                hash_digest = hash_object.digest()
                edge_hash32 = int.from_bytes(hash_digest[-4:], byteorder='little', signed=False)
                if edge_hash32 in apprears:
                    pos_cnt += 1
                cnt += 1
            else:
                break
    print("{}\% postive, {}/{}".format(pos_cnt * 100.0 / cnt, pos_cnt, cnt))

process_tao()