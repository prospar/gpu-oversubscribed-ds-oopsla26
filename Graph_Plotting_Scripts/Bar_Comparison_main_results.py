from pathlib import Path
import argparse
import re

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent

# Algorithms to compare
algorithms = ["MI", "DR", "DU", "SR", "SU", "SUR", "DUL", "ZZ"]

# Oversubscription levels
oversub_levels = [0, 25, 50, 75, 100]


def build_dataset(results_folder, folder, kernel):
    """
    results_folder : e.g. results_HTOVS
    folder         : e.g. inserts, search_positive, search_negative
    kernel         : insert, search, delete
    """

    pattern = re.compile(
        rf"Total time taken by {re.escape(kernel)} kernel\s*(?:\(including sort\)|including sort)?\s*\(ms\):\s*([^\s]+)",
        re.IGNORECASE,
    )
    data = {"Oversubscription Level": oversub_levels}

    for algo in algorithms:
        values = []

        for level in oversub_levels:
            logfile = ROOT / results_folder / folder / algo / f"{level}.log"

            if not logfile.exists():
                print(f"[Missing] {logfile}")
                values.append(np.nan)
                continue

            with open(logfile, "r") as f:
                text = f.read()

            match = pattern.search(text)

            if match:
                values.append(float(match.group(1)))
            else:
                print(f"[No match] {logfile}")
                values.append(np.nan)

        data[algo] = values

    return data


def main():

    parser = argparse.ArgumentParser(
        description="Plot speedup between two implementations."
    )

    parser.add_argument(
        "results_folder1",
        help="First results folder (e.g. results_HTOVS)"
    )

    parser.add_argument(
        "results_folder2",
        help="Second results folder (e.g. results_HTUVM)"
    )

    parser.add_argument(
        "folder",
        help="Folder containing logs (e.g. inserts, search_positive, search_negative)"
    )

    parser.add_argument(
        "kernel",
        choices=["insert", "search", "delete"],
        help="Kernel name to parse from logs"
    )

    args = parser.parse_args()

    # Read datasets
    data1 = build_dataset(
        args.results_folder1,
        args.folder,
        args.kernel
    )

    data2 = build_dataset(
        args.results_folder2,
        args.folder,
        args.kernel
    )

    df1 = pd.DataFrame(data1)
    df2 = pd.DataFrame(data2)

    print(f"\nResults from {args.results_folder1}")
    print(df1)

    print(f"\nResults from {args.results_folder2}")
    print(df2)

    # --------------------------------------------------
    # Compute speedup (Folder1 / Folder2)
    # --------------------------------------------------

    speedup = pd.DataFrame()

    for algo in algorithms:
        speedup[algo] = df1[algo] / df2[algo]

    speedup["Oversubscription Level"] = df1["Oversubscription Level"]

    print("\nSpeedup")
    print(speedup)

    # --------------------------------------------------
    # Plot
    # --------------------------------------------------

    colors = [
        "red",
        "green",
        "blue",
        "yellow",
        "purple",
        "brown",
        "orange",
        "black",
    ]

    bar_width = 0.10
    group_spacing = 0.85

    x = np.arange(len(speedup)) * group_spacing

    offsets = (
        np.arange(len(algorithms)) * bar_width
        - (len(algorithms) - 1) * bar_width / 2
    )

    fig, ax = plt.subplots(figsize=(9, 4))

    for i, algo in enumerate(algorithms):
        ax.bar(
            x + offsets[i],
            speedup[algo],
            width=bar_width,
            color=colors[i],
            edgecolor="black",
            linewidth=0.8,
            label=algo,
        )

    ax.set_xlabel(
        "Oversubscription Level (%)",
        fontsize=14,
    )

    ax.set_ylabel(
        "Speedup",
        fontsize=14,
    )

    ax.set_xticks(x)
    ax.set_xticklabels(speedup["Oversubscription Level"], fontsize=12)

    ax.tick_params(axis="y", labelsize=12)

    ax.grid(axis="y", linestyle="--", alpha=0.6)
    ax.set_axisbelow(True)

    ax.axhline(1.0, color="black", linewidth=1)

    ax.legend(
        ncol=8,
        loc="upper center",
        bbox_to_anchor=(0.5, 1.20),
        frameon=False,
        fontsize=11,
    )

    plt.tight_layout()

    plt.savefig("speedup.pdf", dpi=300)


if __name__ == "__main__":
    main()