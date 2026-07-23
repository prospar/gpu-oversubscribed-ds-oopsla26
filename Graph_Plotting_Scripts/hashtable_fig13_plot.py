from pathlib import Path
import argparse
import re

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
import matplotlib as mpl

mpl.rcParams.update({
    "font.family": "Linux Biolinum O",
    "pdf.fonttype": 42,
    "ps.fonttype": 42,
    "pdf.use14corefonts": False,
})

ROOT = Path(__file__).resolve().parent.parent

# Oversubscription levels
levels = [-25, 0, 25, 50, 75, 100]

# Policies
policies = ["MI", "DR", "DU", "SR", "SU", "SUR", "DUL", "ZZ"]


def build_dataset(results_folder):
    """
    Reads:
        results_RM/<results_folder>/<policy>/<oversub>.log

    Extracts:
        Total remote mappings to CPU: <value>
    """

    data = {"Oversubscription Level": levels}

    pattern = re.compile(r"Total remote mappings to CPU:\s*(\d+)")

    for policy in policies:

        values = []

        for level in levels:

            logfile = (
                ROOT
                / "results_RM"
                / results_folder
                / policy
                / f"{level}.log"
            )

            if not logfile.exists():
                print(f"[Missing] {logfile}")
                values.append(np.nan)
                continue

            with open(logfile, "r") as f:
                text = f.read()

            matches = pattern.findall(text)

            if matches:
                values.append(float(matches[-1]))
            else:
                print(f"[No match] {logfile}")
                values.append(np.nan)

        data[policy] = values

    return pd.DataFrame(data)


def main():

    parser = argparse.ArgumentParser(
        description="Compare remote mappings from two result directories."
    )

    parser.add_argument(
        "dir1",
        help="First directory inside results_RM (e.g. insert_htuvm)"
    )

    parser.add_argument(
        "dir2",
        help="Second directory inside results_RM (e.g. insert_htovs)"
    )

    args = parser.parse_args()

    # Read datasets
    df1 = build_dataset(args.dir1)
    df2 = build_dataset(args.dir2)

    # Convert to thousands
    for col in df1.columns[1:]:
        df1[col] /= 1000
        df2[col] /= 1000

    # Plot settings
    y_keys = ["MI", "DR", "DU", "SR", "SU", "SUR", "DUL", "ZZ"]
    x_key = "Oversubscription Level"

    colors = [
        "lightgray",
        "silver",
        "black",
        "dimgray",
        "gray",
        "gainsboro",
        "darkslategray",
        "darkgray",
    ]

    plt.figure(figsize=(10, 5))

    handles_metric = []

    for policy, color in zip(y_keys, colors):

        # First directory (solid)
        plt.plot(
            df1[x_key],
            df1[policy],
            linestyle="-",
            color=color,
            marker="o",
            markersize=5,
            markeredgecolor="black",
            markeredgewidth=0,
        )

        # Second directory (dashed)
        plt.plot(
            df2[x_key],
            df2[policy],
            linestyle="--",
            color=color,
            marker="o",
            markersize=5,
            markeredgecolor="black",
            markeredgewidth=0,
        )

        handles_metric.append(Patch(color=color, label=policy))

    # Legend labels from directory names
    label1 = args.dir1.replace("insert_", "").replace("_", "-").upper()
    label2 = args.dir2.replace("insert_", "").replace("_", "-").upper()

    line_solid = plt.Line2D(
        [0], [0],
        color="black",
        lw=2,
        linestyle="-",
        label=label1,
    )

    line_dashed = plt.Line2D(
        [0], [0],
        color="black",
        lw=2,
        linestyle="--",
        label=label2,
    )

    # Policy legend
    first_legend = plt.legend(
        handles=handles_metric,
        loc="upper left",
        fontsize=14,
        ncol=2,
    )
    plt.gca().add_artist(first_legend)

    # Directory legend
    plt.legend(
        handles=[line_solid, line_dashed],
        loc="center right",
        fontsize=14,
    )

    plt.xlabel(
        "Oversubscription Level (in %)",
        fontsize=20,
    )

    plt.ylabel(
        "Remote Mappings\n($\\times1000$)",
        fontsize=20,
        labelpad=0,
    )

    plt.xlim(-30, 105)

    plt.xticks(
        levels,
        levels,
        fontsize=16,
    )

    plt.ylim(-5, 120)

    plt.yticks(
        np.arange(0, 121, 20),
        fontsize=16,
    )

    plt.grid(
        True,
        which="major",
        axis="both",
        linestyle="--",
        linewidth=0.6,
    )

    plt.tight_layout()

    plt.savefig(
        "comparison_remote_mappings.pdf",
        dpi=300,
        bbox_inches="tight",
    )

    plt.show()


if __name__ == "__main__":
    main()