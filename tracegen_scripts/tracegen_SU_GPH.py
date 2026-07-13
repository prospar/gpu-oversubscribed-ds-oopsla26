import os
import numpy as np
from pathlib import Path

TOTAL = 5_000_000_00  # 50e7


def generate_random_permutation(
    output_dir=".",
    filename="insert_trace-400e7-random-no-dup.bin",
):
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, filename)

    rng = np.random.default_rng()

    # print("Allocating array...")
    arr = np.arange(1, TOTAL + 1, dtype=np.uint32)

    # print("Shuffling...")
    rng.shuffle(arr)

    # print("Writing to disk...")
    arr.tofile(output_path)

    print("Done!")


if __name__ == "__main__":
    
    
    generate_random_permutation(
        output_dir="./../gph_opensource_copy/datasource/",
        filename="insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE.bin",
    )