import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
import matplotlib as mpl

mpl.rcParams.update({
    "font.family": "Linux Biolinum O",
    "pdf.fonttype": 42,   # TrueType (ACM safe)
    "ps.fonttype": 42,
    "pdf.use14corefonts": False,  # IMPORTANT
})

# Given data
data_app1 = {
    'Input size': [1.5e9, 2e9, 2.5e9, 3e9, 3.5e9, 4e9],
    'Page Faults': [0, 1122891, 1404299, 1686744, 1968281, 2036595],
    'Remote Mappings': [32456, 49800, 64088, 78366, 92441, 105930]
}

# Extract and scale data
x = data_app1['Input size']
page_faults_scaled = [pf / 1e4 for pf in data_app1['Page Faults']]
remote_mappings_scaled = [rm / 1e3 for rm in data_app1['Remote Mappings']]

# Create figure and left axis
fig, ax1 = plt.subplots()

# Left Y-axis plot
line1, = ax1.plot(
    x, page_faults_scaled,
    color='red', marker='x',
    label=r'Page Faults ($\times 10^{4}$)'
)
ax1.set_xlabel(r"Input Size ($\times 10^{9}$)",fontsize = 20)
ax1.set_ylabel(r'Page Faults ($\times 10^{4}$)',fontsize = 20)
ax1.set_ylim(-10, 210)   # <-- padding below 0
ax1.set_yticks(range(0, 201, 50))  # from 0 to 200, step 50
ax1.tick_params(axis='y', labelsize=20)

# Grid lines
ax1.grid(True, which='both', axis='both', linestyle='--', alpha=0.6)

# Right Y-axis plot
ax2 = ax1.twinx()
line2, = ax2.plot(
    x, remote_mappings_scaled,
    color='red', marker='o',
    label=r'Remote Mappings ($\times 10^{3}$)'
)
ax2.set_ylabel(r'Remote Mappings ($\times 10^{3}$)',fontsize = 20)
ax2.set_ylim(-10, 210)   # <-- same padding
ax2.set_yticks(range(0, 201, 50))
ax2.tick_params(axis='y', labelsize=20)

# Combined legend
# --- First legend: data series ---
lines = [line1, line2]
labels = [line.get_label() for line in lines]
legend1 = ax1.legend(lines, labels, loc="lower right", fontsize=16)

# --- Second legend: line type ---
mi_insert_line = Line2D(
    [0], [0],
    color='red',
    linestyle='-',
    label='MI Insert'
)

legend2 = ax1.legend(
    handles=[mi_insert_line],
    loc="upper left",
    fontsize=14
)

# Keep both legends
ax1.add_artist(legend1)

# Set X-ticks at the actual input-size values
ax1.set_xticks(x)
ax1.set_xticklabels([f"{v/1e9:.1f}" for v in x], fontsize=20)

plt.savefig("PF_RM.pdf", dpi=300, bbox_inches="tight")
plt.show()
