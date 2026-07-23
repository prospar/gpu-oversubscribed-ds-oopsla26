import csv
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

csv_file = "figures_skiplist/fig6b_study.csv"

df = pd.read_csv(csv_file)
print(df)
# Keep only the trace types you need
# df = df[df["Trace Type"].isin(["MI", "SU"])]

# Pivot the table
df1 = (
    df.pivot(
        index="Input Size",
        columns="Impl",
        values=["Insert Time", "Search Time"]
    )
    .sort_index()
)

print(df1)

# Rename columns
df1.columns = [
    f"{'Build' if metric == 'Insert Time' else 'Classify'}"
    for metric, impl in df1.columns
]

print(df1)

# Reorder columns
'''
df1 = df1[
    ["Build", "Classify"]
]
print(df1)
'''

# Make Input Size a column
df1 = df1.reset_index()

print(df1)


x_key = "Input Size"
y_keys = ["Build", "Classify"]

colors = ["red", "blue"]
markers = ["o", "o"]
linestyles = ["-", "--"]

plt.figure(figsize=(6, 5))

for y_key, color, marker, linestyle in zip(y_keys, colors, markers, linestyles):
    plt.plot(
        df1[x_key],
        df1[y_key],
        label=y_key,
        color=color,
        marker=marker,
        linestyle=linestyle,
        linewidth=2,
        markersize=7,
    )

# X-axis
plt.xlabel("Oversubscription (%)", fontsize=20)
plt.xticks(
    df1[x_key],
    [f"{x}" for x in df1[x_key]],
    fontsize=16,
)

# Y-axis
plt.ylabel("Time (s)", fontsize=20)
plt.yscale("log")
plt.tick_params(axis="y", labelsize=16)

# Grid and legend
plt.grid(True, which="both", linestyle="--", alpha=0.5)
plt.legend(fontsize=13, ncol=2)

plt.tight_layout()
plt.savefig("figures_skiplist/fig_6b.pdf", dpi=300)
plt.show()
# '''