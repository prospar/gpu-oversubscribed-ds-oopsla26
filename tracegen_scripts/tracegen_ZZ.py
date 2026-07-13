import os
import numpy as np
from pathlib import Path

TOTAL_ELEMENTS = 4_000_000_000
BUFFER_SIZE = 10_000_000  # Number of uint32s written at a time


def generate_trace(
    output_dir=".",
    filename="insert_trace-400e7-alternating.bin",
):
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, filename)

    with open(output_path, "wb") as f:
        buffer = np.empty(BUFFER_SIZE, dtype=np.uint32)
        idx = 0

        left = 1
        right = TOTAL_ELEMENTS

        while left <= right:
            buffer[idx] = left
            idx += 1
            left += 1

            if left <= right:
                buffer[idx] = right
                idx += 1
                right -= 1

            if idx == BUFFER_SIZE:
                buffer.tofile(f)
                idx = 0

        if idx > 0:
            buffer[:idx].tofile(f)

    print("Done!")


if __name__ == "__main__":
    
    output_dir = Path("./../Traces/")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    generate_trace(
        output_dir="./../Traces/",
        filename="insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_ZigZag.bin",
    )