import os
import numpy as np

UINT32_MAX = 2**32 - 1  # 4294967295


def generate_monotonic_keys(
    max_value: int = UINT32_MAX,
    output_dir: str = ".",
    filename: str = "monotonic_uint32.bin",
    chunk_size: int = 10_000_000,
):
    """
    Generate a binary file containing the monotonically increasing sequence:
        1, 2, 3, ..., UINT32_MAX

    Values are stored as uint32.
    """

    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, filename)

    with open(output_path, "wb") as f:
        current = 1

        while current <= max_value:
            end = min(current + chunk_size - 1, max_value)

            arr = np.arange(
                current,
                end + 1,
                dtype=np.uint32
            )

            arr.tofile(f)

            # print(f"Wrote [{current}, {end}]")

            current = end + 1

    print("Done!")


if __name__ == "__main__":
    generate_monotonic_keys(
        max_value=400_000_0000,
        output_dir="/data/heterods-trace/",
        filename="insert_trace-400e7-100-add-no-dup-MONOTONIC_INCREASE.bin",
        chunk_size=10_000_000,
    )