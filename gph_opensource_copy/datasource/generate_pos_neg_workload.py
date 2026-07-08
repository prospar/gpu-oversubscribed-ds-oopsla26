import random


# ratios are in [0, 100]
def generate_query(DATASET_NAME, pos_ratio, workload_size=200000000):
    DATASET_KEY_FILE_NAME = "{}_key_encoded.txt".format(DATASET_NAME)
    neg_ratio = 100 - pos_ratio
    all_integers = set()


    # Read dataset.txt and store all integers in a set
    print("Read {}...".format(DATASET_KEY_FILE_NAME))
    with open(DATASET_KEY_FILE_NAME, 'r') as file:
        for line in file:
            integer = int(line.strip())
            all_integers.add(integer)
    all_integers_list = list(all_integers)
    
    total_num = workload_size
    num_positive = int(pos_ratio * 0.01 * total_num)
    num_negative = int(neg_ratio * 0.01 * total_num)

    target_file = '{}_workload_pos{}_size{}.txt'.format(DATASET_NAME, pos_ratio, workload_size)
    print("Generating data for {}...".format(target_file))
    res = []
    # Write num_positive integers that are in dataset.txt
    for _ in range(num_positive):
        integer = random.choice(all_integers_list)
        res.append(str(integer)+'\n')
    # Write num_negative integers that are not in dataset.txt
    for _ in range(num_negative):
        integer = random.randint(1, 2**32 - 2)
        while integer in all_integers:
            integer = random.randint(1, 2**32 - 2)
        res.append(str(integer)+'\n')
    print("Shuffling {}...".format(target_file))
    random.shuffle(res)
    print("Write to {}...".format(target_file))
    with open(target_file, 'w') as file:
        file.writelines(res)
    print("Complete")

if __name__ == "__main__":
    # generate_query("lineitem", 0)
    # generate_query("lineitem", 25)
    # generate_query("lineitem", 50)
    # generate_query("lineitem", 75)
    # generate_query("lineitem", 100)

    # generate_query("reddit", 0)
    # generate_query("reddit", 25)
    # generate_query("reddit", 50)
    # generate_query("reddit", 75)
    # generate_query("reddit", 100)

    generate_query("random", 0)
    generate_query("random", 25)
    generate_query("random", 50)
    generate_query("random", 75)
    generate_query("random", 100)