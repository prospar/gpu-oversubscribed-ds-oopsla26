import os
import numpy as np

TOTAL_ELEMENTS = 4_000_000_000
NUM_CHUNKS = 8
CHUNK_SIZE = TOTAL_ELEMENTS // NUM_CHUNKS  # 500,000,000


def generate_trace(
    output_dir=".",
    filename="insert_trace-400e7-8chunks-shuffled.bin",
    seed=42,
):
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, filename)

    rng = np.random.default_rng(seed)

    with open(output_path, "wb") as f:

        for chunk in range(NUM_CHUNKS):

            # print(f"Generating chunk {chunk + 1}/{NUM_CHUNKS}")

            start = chunk * CHUNK_SIZE + 1
            end = (chunk + 1) * CHUNK_SIZE

            arr = np.arange(start, end + 1, dtype=np.uint32)

            rng.shuffle(arr)

            arr.tofile(f)

            del arr

    print("Done!")


if __name__ == "__main__":
    output_dir = Path("./../Traces/")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    generate_trace(
        output_dir="./../Traces/",
        filename="insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE.bin",
        seed=42,
    )