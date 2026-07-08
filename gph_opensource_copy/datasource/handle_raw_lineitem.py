import hashlib
from collections import defaultdict

RAW_DATA_FILE = 'lineitem_0_1_3_9.txt'
OUTPUT_KEY_FILE = 'lineitem_key_encoded.txt'
OUTPUT_VALUE_FILE = 'lineitem_value_encoded.txt'

def process_lineitem():
    apprears = set()
    with open(RAW_DATA_FILE, 'r+', encoding="utf-8") as file, open(OUTPUT_KEY_FILE, 'w') as f_name, open(OUTPUT_VALUE_FILE, 'w') as f_author:
        while True:
            line = file.readline()
            if line:
                line = line.strip()   
                data1,data2,data3,data4 = line.split('|')

                hash_object = hashlib.sha256("{}|{}|{}".format(data1,data2,data3).encode())
                hash_digest = hash_object.digest()
                uint32_int = int.from_bytes(hash_digest[-4:], byteorder='little', signed=False)
                if (uint32_int in apprears): continue
                apprears.add(uint32_int)
                f_name.write(str(uint32_int) + '\n')

                hash_object = hashlib.sha256(data4.encode())
                hash_digest = hash_object.digest()
                uint32_int = int.from_bytes(hash_digest[-4:], byteorder='little', signed=False)
                f_author.write(str(uint32_int) + '\n')
            else:
                break
    print("process_raw_reddit_name_author convert complete")

def collect_meta(file_name):
    with open(file_name, "r+") as f:
        data = []
        data.extend([int(line) for line in f.readlines()])
        dataset = set(data)
        print("File {} meta -> {} lines, {} unique values, value range [{},{}]".format(file_name, len(data), len(dataset), min(dataset), max(dataset) ))

if __name__ == "__main__":
    process_lineitem()
    collect_meta(OUTPUT_KEY_FILE)
    collect_meta(OUTPUT_VALUE_FILE)
