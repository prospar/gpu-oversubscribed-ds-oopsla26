from pathlib import Path
import argparse
import re

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent

# Applications
algorithms = [
    "Metagenomics Build",
    "Metagenomics Classify",
    "K-mer Counter",
]

# Oversubscription levels
oversub_levels = [10, 30, 50]


def parse_metacache(logfile):
    """
    Parse MetaCache log and return build and classify times.
    """

    if not logfile.exists():
        print(f"[Missing] {logfile}")
        return {
            "Metagenomics Build": np.nan,
            "Metagenomics Classify": np.nan,
        }

    with open(logfile, "r") as f:
        text = f.read()

    build = re.search(
        r"Total time taken \(ms\):\s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)",
        text,
    )

    classify = re.search(
        r"Total time taken\(classify\) \(ms\):\s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)",
        text,
    )

    return {
        "Metagenomics Build":
            float(build.group(1)) if build else np.nan,
        "Metagenomics Classify":
            float(classify.group(1)) if classify else np.nan,
    }


def parse_kmer(logfile):
    """
    Parse K-mer counter log.
    """

    if not logfile.exists():
        print(f"[Missing] {logfile}")
        return {"K-mer Counter": np.nan}

    with open(logfile, "r") as f:
        text = f.read()

    match = re.search(
        r"Total time taken \(ms\):\s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)",
        text,
    )

    return {
        "K-mer Counter":
            float(match.group(1)) if match else np.nan
    }


def build_dataset(results_folder):
    """
    results_folder:
        htov
        htuvm
    """

    data = {
        "Oversubscription Level": oversub_levels,
        "Metagenomics Build": [],
        "Metagenomics Classify": [],
        "K-mer Counter": [],
    }

    for level in oversub_levels:

        meta_log = (
            ROOT
            / "results_applications"
            / results_folder
            / str(level)
            / "metacache.log"
        )

        kmer_log = (
            ROOT
            / "results_applications"
            / results_folder
            / str(level)
            / "kmer.log"
        )

        meta = parse_metacache(meta_log)
        kmer = parse_kmer(kmer_log)

        data["Metagenomics Build"].append(
            meta["Metagenomics Build"]
        )

        data["Metagenomics Classify"].append(
            meta["Metagenomics Classify"]
        )

        data["K-mer Counter"].append(
            kmer["K-mer Counter"]
        )

    return pd.DataFrame(data)


def main():

    parser = argparse.ArgumentParser(
        description="Plot application speedup."
    )

    parser.add_argument(
        "results_folder1",
        help="First results folder (e.g. htov)"
    )

    parser.add_argument(
        "results_folder2",
        help="Second results folder (e.g. htuvm)"
    )

    args = parser.parse_args()

    df1 = build_dataset(args.results_folder1)
    df2 = build_dataset(args.results_folder2)

    print(f"\nResults from {args.results_folder1}")
    print(df1)

    print(f"\nResults from {args.results_folder2}")
    print(df2)

    # --------------------------------------------------
    # Compute speedup
    # --------------------------------------------------

    speedup = pd.DataFrame()

    for algo in algorithms:
        speedup[algo] = df1[algo] / df2[algo]

    speedup["Oversubscription Level"] = oversub_levels

    print("\nSpeedup")
    print(speedup)

    # --------------------------------------------------
    # Plot
    # --------------------------------------------------

    colors = [
        "red",
        "blue",
        "green",
    ]

    bar_width = 0.20
    group_spacing = 1.0

    x = np.arange(len(oversub_levels)) * group_spacing

    offsets = (
        np.arange(len(algorithms)) * bar_width
        - (len(algorithms) - 1) * bar_width / 2
    )

    fig, ax = plt.subplots(figsize=(7, 4))

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
    ax.set_xticklabels(
        oversub_levels,
        fontsize=12,
    )

    ax.tick_params(axis="y", labelsize=12)

    ax.grid(
        axis="y",
        linestyle="--",
        alpha=0.6,
    )

    ax.set_axisbelow(True)

    ax.axhline(
        1.0,
        color="black",
        linewidth=1,
    )

    ax.legend(
        ncol=3,
        loc="upper center",
        bbox_to_anchor=(0.5, 1.18),
        frameon=False,
        fontsize=11,
    )

    plt.tight_layout()
    plt.savefig("speedup.pdf", dpi=300)


if __name__ == "__main__":
    main()