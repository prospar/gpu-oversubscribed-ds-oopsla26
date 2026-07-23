import csv
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

csv_file = "figures_skiplist/fig4c_study_skiplist.csv"

df = pd.read_csv(csv_file)
print(df)
# Keep only the trace types you need
df = df[df["Trace Type"].isin(["MI", "SU"])]

# Pivot the table
df1 = (
    df.pivot(
        index="Input Size",
        columns="Trace Type",
        values=["Insert Time", "Search Time"]
    )
    .sort_index()
)

# Rename columns
df1.columns = [
    f"{trace} {'Insert' if metric == 'Insert Time' else 'Search'}"
    for metric, trace in df1.columns
]

# Reorder columns
df1 = df1[
    ["MI Insert", "SU Insert", "MI Search", "SU Search"]
]

# Make Input Size a column
df1 = df1.reset_index()

print(df1)



x_key = "Input Size"
y_keys = ["SU Insert", "SU Search", "MI Insert", "MI Search"]

colors = ["red", "red", "blue", "blue"]
markers = ["o", "^", "o", "^"]
linestyles = ["-", "--", "-", "--"]

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
plt.xlabel("Input Size (×10⁹)", fontsize=20)
plt.xticks(
    df1[x_key],
    [f"{x/1e9:.1f}" for x in df1[x_key]],
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
plt.savefig("figures_skiplist/fig4_c.pdf", dpi=300)
plt.show()