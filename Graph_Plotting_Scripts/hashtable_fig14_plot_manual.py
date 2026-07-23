import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib as mpl

mpl.rcParams.update({
    "font.family": "Linux Biolinum O",
    "pdf.fonttype": 42,
    "ps.fonttype": 42,
    "pdf.use14corefonts": False,
})

# -------------------------
# Data
# -------------------------


#For GPH
data_app1 = {
    'Oversubscription Level': [25, 50, 75, 100],
    'SU': [82953.4, 95757.2, 105124, 109976],
    'DU': [83038.8, 95352, 105088, 110686],
    'MI': [78987.7, 95616.6, 104864, 109872]
}

#For HTOVS
data_app2 = {
    'Oversubscription Level': [25, 50, 75, 100],
    'SU': [37727.3, 38418.4, 39197.2, 51908.9],
    'DU': [6062.81, 6289.51, 6304.02, 20573.4],
    'MI': [2232.3, 2401.5, 2572.4, 17741.3]
}

# -------------------------
# Convert to DataFrames
# -------------------------

df1 = pd.DataFrame(data_app1)
df2 = pd.DataFrame(data_app2)

time_cols = [
    'MI',
    'DU',
    'SU',
]

df1[time_cols] /= 1000.0
df2[time_cols] /= 1000.0

# -------------------------
# Plot settings
# -------------------------

y_keys = [
    'MI',
    'DU',
    'SU',
]

colors = [
    'lightgray',
    'black',
    'gray',
]

bar_width = 0.10
group_spacing = 0.85
n_bars = len(y_keys)

x = np.arange(len(df1['Oversubscription Level'])) * group_spacing
bar_offsets = np.arange(n_bars) * bar_width - (n_bars - 1) / 2 * bar_width

# -------------------------
# Overflow annotation
# -------------------------

def annotate_overflow(ax, x_positions, values, ymax, bar_width, key):
    base_fontsize = 10
    ref_bar_width = 0.10
    fontsize = base_fontsize * (bar_width / ref_bar_width)
    fontsize = max(8, min(fontsize, 12))

    if key == "MI":
        font_color = "black"
    elif key == "DU":
        font_color = "white"
    else:
        font_color = "black"

    for xpos, val in zip(x_positions, values):
        if val > ymax:
            ax.text(
                xpos,
                ymax / 2 + 0.45,
                f"{val:.1f}",
                ha='center',
                va='center',
                rotation=90,
                fontsize=16,
                color=font_color,
                clip_on=True,
            )

# -------------------------
# Create figure
# -------------------------

fig, ax = plt.subplots(figsize=(10, 5))

for i, (key, color) in enumerate(zip(y_keys, colors)):
    values = df1[key] / df2[key]
    ax.bar(x + bar_offsets[i], values, bar_width, color=color, alpha=0.9)

ax.set_xlabel("Oversubscription Level (in %)", fontsize=20)
ax.set_ylabel("Speedup", fontsize=20)
ax.tick_params(axis='y', labelsize=16)
ax.set_xticks(x)
ax.margins(x=0.01)
ax.set_xticklabels(df1['Oversubscription Level'], fontsize=16)
ax.set_ylim(1, 4)
ax.set_yticks(np.arange(1, 4.5, 1))
ax.grid(axis='y', linestyle='--', alpha=0.6)
ax.set_axisbelow(True)

ymax = ax.get_ylim()[1]
for i, key in enumerate(y_keys):
    xpos = x + bar_offsets[i]
    values = df1[key] / df2[key]
    annotate_overflow(ax, xpos, values, ymax, bar_width, key)

handles = [plt.Rectangle((0, 0), 1, 1, color=c) for c in colors]
fig.legend(
    handles,
    y_keys,
    loc='lower center',
    ncol=1,
    frameon=True,
    fontsize=18,
    columnspacing=1.0,
    handlelength=1.5,
    handleheight=0.75,
    bbox_to_anchor=(0.5, 0.67),
)

plt.tight_layout()

plt.savefig(
    "comparison_speedup_insert_gph.pdf",
    dpi=300,
)