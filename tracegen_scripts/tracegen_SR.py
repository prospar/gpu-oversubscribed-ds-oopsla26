import os
import numpy as np

TOTAL = 4_000_000_000
UNIQUE = 3_200_000_000
DUPLICATES = TOTAL - UNIQUE


def generate_trace(
    output_dir=".",
    filename="insert_trace-400e7-random-20dup.bin",
    duplicate_chunk=10_000_000,
):
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, filename)

    rng = np.random.default_rng()

    # print("Allocating permutation array...")
    perm = np.arange(1, TOTAL + 1, dtype=np.uint32)

    # print("Randomly shuffling all keys...")
    rng.shuffle(perm)

    # print("Allocating final array...")
    final = np.empty(TOTAL, dtype=np.uint32)

    # print("Copying unique keys...")
    final[:UNIQUE] = perm[:UNIQUE]

    del perm

    # print("Generating duplicates...")

    pos = UNIQUE
    while pos < TOTAL:
        n = min(duplicate_chunk, TOTAL - pos)

        idx = rng.integers(
            0,
            UNIQUE,
            size=n,
            dtype=np.int64,
        )

        final[pos:pos + n] = final[idx]

        pos += n

        # print(f"Generated {pos-UNIQUE:,}/{DUPLICATES:,} duplicates", end="\r")

    # print("\nFinal shuffle...")
    rng.shuffle(final)

    # print("Writing to disk...")
    final.tofile(output_path)

    print("Done!")


if __name__ == "__main__":
    
    output_dir = Path("./../Traces/")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    generate_trace(
        output_dir="./../Traces/",
        filename="insert_trace-400e7-100-add-20-dup-SPARSE_REPEAT.bin",
        duplicate_chunk=10_000_000,
    )