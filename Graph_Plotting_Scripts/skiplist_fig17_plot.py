import pandas as pd
import numpy as np
import matplotlib.pyplot as plt


def geometric_mean(values):
    values = np.asarray(values, dtype=float)
    return np.exp(np.mean(np.log(values)))

# Read CSV
df = pd.read_csv("figures_skiplist/fig_17_study.csv")

# Create a flat table
pivot = df.pivot(
    index=["Input Size"],
    columns="Impl",
    values=["Insert Time", "Search Time"]
).reset_index()


# Compute speedup
build_speedup = (
    pivot[("Insert Time", "sluvm_classifier")] /
    pivot[("Insert Time", "slovs_classifier")]
)

classify_speedup = (
    pivot[("Search Time", "sluvm_classifier")] /
    pivot[("Search Time", "slovs_classifier")]
)

kmer_speedup = (
    pivot[("Insert Time", "sluvm_kmer")] /
    pivot[("Insert Time", "slovs_kmer")]
)
input_sizes = sorted(df["Input Size"].unique())

build_speedup = build_speedup.tolist()
classify_speedup = classify_speedup.tolist()
kmer_speedup = kmer_speedup.tolist()
print(build_speedup)
print(classify_speedup)
print(kmer_speedup)
build_speedup.append(round(geometric_mean(build_speedup),2))
classify_speedup.append(round(geometric_mean(classify_speedup),2))
kmer_speedup.append(round(geometric_mean(kmer_speedup),2))
print(build_speedup)
print(classify_speedup)
print(kmer_speedup)

width = 0.25

x_labels=[f"{s}" for s in input_sizes]
x_labels.append("Geomean")
x = np.arange(len(x_labels))

fig, ax = plt.subplots(figsize=(8, 5))

ax.bar(
    x - width,
    build_speedup,
    width,
    label="Metagenomics Build",
    edgecolor="black"
)

ax.bar(
    x,
    classify_speedup,
    width,
    label="Metagenomics Classify",
    edgecolor="black"
)

ax.bar(
    x + width,
    kmer_speedup,
    width,
    label="K-mer Counter",
    edgecolor="black"
)

for container in ax.containers:
    ax.bar_label(container, fmt="%.1f", fontsize=8, padding=2)

ax.axhline(1.0, color="black", linestyle="--")
ax.set_ylabel("Speedup")
# ax.set_title("Performance for Real-world applications")
ax.grid(axis="y", alpha=0.3)

ax.set_xticks(x)
ax.set_xticklabels(x_labels)
ax.set_xlabel("Oversubscription (%)")

plt.tight_layout()
plt.savefig("figures_skiplist/fig17.pdf", dpi=300)
plt.show()
