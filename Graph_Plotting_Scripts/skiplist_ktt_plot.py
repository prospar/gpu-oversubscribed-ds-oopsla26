import pandas as pd
import numpy as np
import matplotlib.pyplot as plt


def geometric_mean(values):
    values = np.asarray(values, dtype=float)
    return np.exp(np.mean(np.log(values)))

# Read CSV
df = pd.read_csv("figures_skiplist/fig16_study.csv")

# Create a flat table
pivot = df.pivot(
    index=["Input Size", "Trace Type"],
    columns="Impl",
    values=["Insert Time", "Search Time"]
).reset_index()

# Compute speedup
pivot["Insert Speedup"] = (
    pivot[("Insert Time", "sl-uvm-sort")] /
    pivot[("Insert Time", "sl-ovs-sort")]
)

pivot["Search Speedup"] = (
    pivot[("Search Time", "sl-uvm-sort")] /
    pivot[("Search Time", "sl-ovs-sort")]
)

# Keep only required columns
speedup = pd.DataFrame({
    "Input Size": pivot[("Input Size", "")],
    "Trace Type": pivot[("Trace Type", "")],
    "Insert Speedup": pivot["Insert Speedup"],
    "Search Speedup": pivot["Search Speedup"],
})

speedup = speedup.sort_values("Input Size")
print(speedup)


numeric_sizes = np.sort(speedup["Input Size"].unique())

trace_types = ["MI", "DU"]
input_sizes = sorted(speedup["Input Size"].unique())

# input_sizes.append("Geomean")

geo_rows = []
for trace in trace_types:

    d = speedup[speedup["Trace Type"] == trace]

    geo_rows.append({
        "Input Size": "GeoMean",
        "Trace Type": trace,
        "Insert Speedup": geometric_mean(d["Insert Speedup"]),
        "Search Speedup": geometric_mean(d["Search Speedup"]),
    })

geo = pd.DataFrame(geo_rows)
print(geo)

bar_width = 0.25

x_labels=[f"{s/1e9:.2f}" for s in numeric_sizes]
x_labels.append("Geomean")

x = np.arange(len(x_labels))


fig, axes = plt.subplots(2, 1, figsize=(7, 10), sharex=True)

for ax, metric, title in zip(
        axes,
        ["Insert Speedup", "Search Speedup"],
        ["Insert Speedup", "Search Speedup"]):

    for i, trace in enumerate(trace_types):

        vals = []

        for size in input_sizes:
            vals.append(
                speedup.loc[
                    (speedup["Input Size"] == size) &
                    (speedup["Trace Type"] == trace),
                    metric
                ].values[0]
            )

        vals.append(
            geometric_mean(
                speedup.loc[
                    speedup["Trace Type"] == trace,
                    metric
                ]
            )
        )

        ax.bar(
            x + (i-1)*bar_width,
            vals,
            width=bar_width,
            label=trace,
            edgecolor="black"
        )

        # annotate bars
        for xx, yy in zip(x + (i-1)*bar_width, vals):
            ax.text(xx, yy + 0.01, f"{yy:.2f}",
                    ha="center", fontsize=8)

    ax.axhline(1.0, color="black", linestyle="--")
    ax.set_ylabel("Speedup")
    ax.set_title(title)
    ax.grid(axis="y", alpha=0.3)
    ax.legend(title="Trace Type")

axes[1].set_xticks(x)
axes[1].set_xticklabels(x_labels)
axes[1].set_xlabel("Input Size(x10^9)")

plt.tight_layout()
plt.savefig("figures_skiplist/kick_the_tire.pdf", dpi=300)
plt.show()