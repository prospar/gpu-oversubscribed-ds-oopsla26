import os
import tempfile
import numpy as np

TOTAL_ELEMENTS = 4_000_000_000

NUM_CHUNKS = 8
CHUNK_SIZE = TOTAL_ELEMENTS // NUM_CHUNKS          # 500,000,000

UNIQUE_PER_CHUNK = int(CHUNK_SIZE * 0.8)           # 400,000,000
DUPLICATE_PER_CHUNK = CHUNK_SIZE - UNIQUE_PER_CHUNK  #100,000,000


def generate_trace(
    output_dir=".",
    filename="insert_trace.bin",
    seed=42,
):
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, filename)

    rng = np.random.default_rng(seed)

    with open(output_path, "wb") as fout:

        for chunk in range(NUM_CHUNKS):

            # print(f"Generating chunk {chunk+1}/{NUM_CHUNKS}")

            chunk_start = chunk * CHUNK_SIZE + 1
            chunk_end = (chunk + 1) * CHUNK_SIZE

            # --------------------------------------------------
            # Candidate values for this chunk
            # --------------------------------------------------
            values = np.arange(
                chunk_start,
                chunk_end + 1,
                dtype=np.uint32,
            )

            # Choose 400M unique values
            unique = rng.choice(
                values,
                size=UNIQUE_PER_CHUNK,
                replace=False,
                shuffle=False,
            )

            del values

            # Duplicate 100M values
            dup = rng.choice(
                unique,
                size=DUPLICATE_PER_CHUNK,
                replace=True,
            )

            # --------------------------------------------------
            # Disk-backed array
            # --------------------------------------------------
            tmp = tempfile.NamedTemporaryFile(delete=False)
            tmp.close()

            arr = np.memmap(
                tmp.name,
                dtype=np.uint32,
                mode="w+",
                shape=(CHUNK_SIZE,),
            )

            arr[:UNIQUE_PER_CHUNK] = unique
            arr[UNIQUE_PER_CHUNK:] = dup

            del unique
            del dup

            # --------------------------------------------------
            # Shuffle in-place
            # --------------------------------------------------
            perm = rng.permutation(CHUNK_SIZE)

            shuffled_tmp = tempfile.NamedTemporaryFile(delete=False)
            shuffled_tmp.close()

            shuffled = np.memmap(
                shuffled_tmp.name,
                dtype=np.uint32,
                mode="w+",
                shape=(CHUNK_SIZE,),
            )

            shuffled[:] = arr[perm]

            shuffled.tofile(fout)

            del arr
            del shuffled
            del perm

            os.remove(tmp.name)
            os.remove(shuffled_tmp.name)

    print("Done!")


if __name__ == "__main__":
    output_dir = Path("./../Traces/")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    generate_trace(
        output_dir="./../Traces/",
        filename="insert_trace-400e7-100-add-20-dup-DENSE_REPEAT.bin",
        seed=42,
    )