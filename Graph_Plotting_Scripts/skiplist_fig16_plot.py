import pandas as pd
import numpy as np
import matplotlib.pyplot as plt


def geometric_mean(values):
    values = np.asarray(values, dtype=float)
    return np.exp(np.mean(np.log(values)))

label_map = {
    1250000000: "0",
    1500000000: "20",
    1750000000: "40",
    2000000000: "60",
    2250000000: "80",
    2500000000: "100",
    "GeoMean": "GeoMean"
}


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

trace_types = ["SU", "MI", "DU"]
input_sizes = sorted(speedup["Input Size"].unique())

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

x_labels=[f"{s}" for s in numeric_sizes]
x_labels.append("Geomean")

x = np.arange(len(x_labels))


# fig, axes = plt.subplots(2, 1, figsize=(7, 10), sharex=True)
fig, axes = plt.subplots(1, 2, figsize=(14, 5), sharex=True)
labels = [label_map[s] for s in input_sizes]
labels.append("GeoMean")

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

    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.set_xlabel("Oversubscription Level(in %)")
    ax.axhline(1.0, color="black", linestyle="--")

axes[0].set_ylabel("Speedup")
axes[0].set_title("Insert Speedup")
axes[1].set_title("Search Speedup")
# ax.grid(axis="y", alpha=0.3)
handles, labels = axes[0].get_legend_handles_labels()

fig.legend(
    handles,
    labels,
    loc="upper center",
    ncol=3,
    frameon=False,
    bbox_to_anchor=(0.5, 1.05)
)



plt.tight_layout()
plt.savefig("figures_skiplist/fig16.pdf", dpi=300)
plt.show()