from pathlib import Path
import argparse
import re

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.ticker import LogLocator, LogFormatterMathtext

ROOT = Path(__file__).resolve().parent.parent

# Input sizes
input_sizes = [
    1500000000,
    2000000000,
    2500000000,
    3000000000,
    3500000000,
    4000000000,
]


def build_dataset(results_folder):

    patterns = {
        "Insert": re.compile(
            r"Total time taken by insert kernel(?: including sort)? \(ms\):\s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)"
        ),
        "Search": re.compile(
            r"Total time taken by search kernel(?: including sort)? \(ms\):\s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)"
        ),
    }

    workloads = [
        ("MI Insert", "Insert", "MI"),
        ("SU Insert", "Insert", "SU"),
        ("MI Search", "Search", "MI"),
        ("SU Search", "Search", "SU"),
    ]

    data = {"Input Size": input_sizes}

    for label, folder, algo in workloads:

        values = []

        for size in input_sizes:

            logfile = (
                ROOT
                / results_folder
                / folder
                / algo
                / f"{size}.log"
            )

            if not logfile.exists():
                print(f"[Missing] {logfile}")
                values.append(np.nan)
                continue

            with open(logfile, "r") as f:
                text = f.read()

            match = patterns[folder].search(text)

            if match:
                values.append(float(match.group(1)))
            else:
                print(f"[No match] {logfile}")
                values.append(np.nan)

        data[label] = values

    return pd.DataFrame(data)


def main():

    parser = argparse.ArgumentParser(
        description="Plot motivation graph."
    )

    parser.add_argument(
        "results_folder",
        help="Example: results_motivation"
    )

    args = parser.parse_args()

    # Read dataset
    df = build_dataset(args.results_folder)

    print(df)

    # Convert milliseconds to seconds
    for col in df.columns[1:]:
        df[col] = pd.to_numeric(df[col], errors="coerce") / 1000

    # ---------------- Plot ----------------

    plt.figure(figsize=(6, 5))
    ax = plt.gca()

    lines = [
        ("MI Insert", "MI Insert", "red", "x", "-"),
        ("MI Search", "MI Search", "red", "x", "--"),
        ("SU Insert", "SU Insert", "blue", "o", "-"),
        ("SU Search", "SU Search", "blue", "o", "--"),
    ]

    for key, label, color, marker, style in lines:

        ax.plot(
            df["Input Size"],
            df[key],
            label=label,
            color=color,
            marker=marker,
            linestyle=style,
            linewidth=2,
            markersize=8,
        )

    # ---------------- Axis ----------------

    ax.set_xlabel(r"Input size ($\times10^9$)", fontsize=20)
    ax.set_ylabel("Time (sec)", fontsize=20)

    x_min = min(input_sizes)
    x_max = max(input_sizes)
    padding = 0.05 * (x_max - x_min)

    ax.set_xlim(x_min - padding, x_max + padding)

    ax.set_xticks(df["Input Size"])
    ax.set_xticklabels(
        [f"{x / 1e9:.1f}" for x in df["Input Size"]],
        fontsize=18,
    )

    ax.set_yscale("log")
    ax.set_ylim(1, 1e5)

    ax.yaxis.set_major_locator(LogLocator(base=10))
    ax.yaxis.set_major_formatter(LogFormatterMathtext(base=10))

    ax.tick_params(axis="y", labelsize=18)

    # ---------------- Grid ----------------

    ax.grid(
        which="major",
        linestyle="--",
        linewidth=0.6
    )

    # ---------------- Timeout markers ----------------

    cols = [
        "MI Insert",
        "MI Search",
        "SU Insert",
        "SU Search",
    ]

    timeout_mask = df[cols].isna().any(axis=1)

    if timeout_mask.any():

        y_timeout = ax.get_ylim()[0] * 1.5

        ax.scatter(
            df.loc[timeout_mask, "Input Size"],
            [y_timeout] * timeout_mask.sum(),
            marker="x",
            color="black",
            s=120,
            linewidths=2,
            label="Timeout",
            zorder=5,
        )

    # ---------------- Legend ----------------

    ax.legend(
        fontsize=14,
        ncol=2,
        loc="upper right",
        bbox_to_anchor=(0.95, 0.45),
        frameon=True,
    )

    plt.tight_layout()

    plt.savefig(
        "Skiplist_motivation.pdf",
        dpi=300,
        bbox_inches="tight",
    )

    plt.show()


if __name__ == "__main__":
    main()