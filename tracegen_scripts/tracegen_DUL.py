import os
import numpy as np

TOTAL_ELEMENTS = 4_000_000_000
CHUNK_SIZE = 1_000_000_000  # 1e9 elements per chunk
NUM_CHUNKS = TOTAL_ELEMENTS // CHUNK_SIZE

assert TOTAL_ELEMENTS % CHUNK_SIZE == 0


def generate_trace(
    output_dir=".",
    filename="insert_trace-400e7-4chunks-shuffled.bin",
    seed=42,
):
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, filename)

    rng = np.random.default_rng(seed)

    with open(output_path, "wb") as f:
        for chunk in range(NUM_CHUNKS):
            start = chunk * CHUNK_SIZE + 1
            end = (chunk + 1) * CHUNK_SIZE

            arr = np.arange(start, end + 1, dtype=np.uint32)

            # Shuffle only within this 1e9-element chunk
            rng.shuffle(arr)

            arr.tofile(f)

            del arr

    print("Done!")


if __name__ == "__main__":
    generate_trace(
        output_dir="/data/heterods-trace/",
        filename="insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE_1e9_Clusters.bin",
        seed=42,
    )