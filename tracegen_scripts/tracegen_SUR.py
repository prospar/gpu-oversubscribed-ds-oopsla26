import os
import numpy as np

TOTAL_ELEMENTS = 4_000_000_000
NUM_CHUNKS = 8
CHUNK_SIZE = TOTAL_ELEMENTS // NUM_CHUNKS  # 500,000,000


def generate_trace(
    output_dir=".",
    filename="insert_trace-400e7-8chunks-internal-and-chunk-shuffled.bin",
    seed=42,
):
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, filename)

    rng = np.random.default_rng(seed)

    # Shuffle the order of the chunks
    chunk_order = np.arange(NUM_CHUNKS)
    rng.shuffle(chunk_order)

    # print("Chunk order:", chunk_order)

    with open(output_path, "wb") as f:
        for chunk in chunk_order:
            start = chunk * CHUNK_SIZE + 1
            end = (chunk + 1) * CHUNK_SIZE

            arr = np.arange(start, end + 1, dtype=np.uint32)

            # Shuffle within the chunk
            rng.shuffle(arr)

            arr.tofile(f)

            del arr

    print("Done!")


if __name__ == "__main__":
    
    output_dir = Path("./../Traces/")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    generate_trace(
        output_dir="./../Traces/",
        filename="insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_5e8_Random_Clusters.bin",
        seed=42,
    )