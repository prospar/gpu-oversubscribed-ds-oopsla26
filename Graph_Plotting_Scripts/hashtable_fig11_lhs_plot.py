from pathlib import Path
import argparse
import re

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent

# CG sizes
cg_groups = ["CG_4", "CG_8", "CG_16", "CG_32"]

# Oversubscription levels
oversub_levels = [0, 25, 50, 75, 100]


def build_dataset(results_folder, kernel):
    """
    results_folder:
        results_HTOVS
        results_HTUVM

    Directory structure:

    results_folder/
        CG_4/
            0.log
            25.log
            ...
        CG_8/
        CG_16/
        CG_32/
    """

    pattern = re.compile(
        rf"Total time taken by {re.escape(kernel)} kernel\s*(?:\(including sort\)|including sort)?\s*\(ms\):\s*([^\s]+)",
        re.IGNORECASE,
    )

    data = {"Oversubscription Level": oversub_levels}

    for cg in cg_groups:

        values = []

        for level in oversub_levels:

            logfile = ROOT / "results_CG" / results_folder / cg / f"{level}.log"

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

        data[cg] = values

    return pd.DataFrame(data)


def main():

    parser = argparse.ArgumentParser(
        description="Plot HT-OVS vs HT-UVM speedup."
    )

    parser.add_argument(
        "results_folder1",
        help="First results folder (e.g. results_HTOVS)"
    )

    parser.add_argument(
        "results_folder2",
        help="Second results folder (e.g. results_HTUVM)"
    )

    args = parser.parse_args()

    # --------------------------------------------------
    # Read datasets
    # --------------------------------------------------

    df_htovs = build_dataset("htovs", "insert")
    df_htuvm = build_dataset("htuvm", "insert")

    print("\nResults from", args.results_folder1)
    print(df1)

    print("\nResults from", args.results_folder2)
    print(df2)

    # --------------------------------------------------
    # Compute Speedup = HTOVS / HTUVM
    # --------------------------------------------------

    speedup = pd.DataFrame()

    speedup["Oversubscription Level"] = oversub_levels

    for cg in cg_groups:
        speedup[cg] = df1[cg] / df2[cg]

    print("\nSpeedup")
    print(speedup)

    # --------------------------------------------------
    # Plot
    # --------------------------------------------------

    colors = [
        "#4C72B0",
        "#DD8452",
        "#55A868",
        "#C44E52",
    ]

    bar_width = 0.18
    x = np.arange(len(oversub_levels))

    fig, ax = plt.subplots(figsize=(6, 4))

    for i, cg in enumerate(cg_groups):

        ax.bar(
            x + (i - 1.5) * bar_width,
            speedup[cg],
            width=bar_width,
            color=colors[i],
            edgecolor="black",
            linewidth=0.8,
            label=cg.replace("_", ""),
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
    ax.set_xticklabels(oversub_levels)

    ax.tick_params(axis="both", labelsize=12)

    ax.grid(axis="y", linestyle="--", alpha=0.5)
    ax.set_axisbelow(True)

    ax.legend(
        loc="upper right",
        frameon=False,
        fontsize=11,
    )

    plt.tight_layout()

    plt.savefig("cg_speedup.pdf", dpi=300)
    plt.show()


if __name__ == "__main__":
    main()