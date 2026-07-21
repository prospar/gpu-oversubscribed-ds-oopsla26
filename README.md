# gpu-oversubscribed-ds-oopsla26

Space Requirements: At least 50GB or more space is required to store the trace files for the evaluations.
In the bashrc export the absolute path for the traces like: export TRACE_ROOT="absolute/path/for/Traces"


# Trace generations
The trace generation scripts are present in tracegen_scripts folder. Running that will generate all the traces required for the experiments within a new folder call Traces.

# For HTUVM and HTOVS

First run the Makefile with arguments "uvm-opt" and "htovs-opt", this will generate the required binaries of the optimal configurations for both HTUVM and HTOVS in the bin folder under main directory.

Now run the scripts present in benchmark_scripts folder. HTUVM and HTOVS will have separate subfolders for scripts. Under that every kernel will have different scripts like insert, delete, positive search queries and negative search queries. After completion of run the "Bar_Comparison_main_results.py" file in the Graph_Plotting_Scripts folder with the arguments of <results_HTOVS/results_HTUVM/results_CUCO> <results_HTOVS/results_HTUVM/results_CUCO> <insert/delete/search_positive/search_negative> <insert/delete/search>.

The plots for each of the configuration will be generated.

# For Applications

The same steps as HTUVM and HTOVS needs to be followed. The Makefile contains both make commands for metagenomics and k-mer counter applications. After make command run the benchmark script for application under Applications_Scripts subfolder. Then run the graph plotting script: "Bar_Comparison_applications.py" with commands <htovs/htuvm> <htuvm/htovs>.

It will generate the plots for metagenomics.

<!-- For GPH -->

# For GPH

To simualte oversubscription scenarios for GPH update the value in line 72 in the file geph_exp.cuh(gph_opensource_copy_original/perf/geph_exp.cuh)

Value       Oversubscription
12.8        25%
13.33       50%
13.72       75%
14          100%

Simialry to change trace types, update the absolute path of trace files 149-150 and 156-157 in the file perf-final-uitls.cuh(gph_opensource_copy_original/perf/perf-final-uitls.cuh). Always use the absolute path of the trace files in the mentioned lines. The traces for GPH are provided in tracegen_scripts folder.


To build and run GPH:
1) Open a terminal in the gph main directory.
2) Run the command "cmake -B build -DCMAKE_POLICY_VERSION_MINIMUM=3.5"
3) Then type "cd common/"
4) Again run the command "cmake"
5) Then again move to gph main directory.  
6) Next run the command "cmake --build build"
7) Next run the command "cd build/perf"
8) Finally run the command "./perf"

Before running the command ./perf make sure to generate the traces by running the tracegen scripts and also run the file: "generate_pos_neg_workload.py" in the data source folder.

After updating the trace file path or memory reservation the commands(6-8) needs to be ran again.

# For Motivation


#########################

# Instructions to reproduce Skip List results

**For skiplist results: all scripts should be run from `gpu-oversubscribed-ds-oopsla26` folder**

#### Required library version:
- The scripts to reproduce skiplist results use following libraries:

```
Matplotlib version: 3.9.3
NumPy version: 2.1.3
Pandas version: 2.2.3
```

### Sanity check:
- Create the directories for storing traces, results, and figure  
- Verify the installation path and environment variables
- Add an environment variable in the `.bashrc`, e.g., `export SL_TRACE_ROOT=<path of gpu-oversubscribed-ds-oopsls26 directory>/skiplist_traces`


### Motivation Figure (figure 4(c) in the paper)


**Warning: Runtime of motivation results with sparse traces extends into hours for insert and search with oversubcription**

_The script runs only monotonic trace in default setting to complete in reasonable time, uncomment line 91 in the `motivation\_study.sh`to collect result for sparse traces_

- Execute the motivation script present in benchmark_scripts 
```bash
~/gpu-oversubscribed-ds-oopsla26$ bash benchmark_scripts/skiplist_scripts/motivation_study.sh
```

- Parse the log files to generate csv file, generates `motivation_study_skiplist.csv` in path `~/gpu-oversubscribed-ds-oopsla26`
```bash
~/gpu-oversubscribed-ds-oopsla26$ python3 benchmark_scripts/skiplist_scripts/parse_motivation_skiplist_results.py skiplist_results/motivation_study
```
- Generating figure 4c of the paper. The file `fig4_c.pdf` will be generated in the `figures_skiplist` folder
```bash
~/gpu-oversubscribed-ds-oopsla26$ python3 Graph_Plotting_Scripts/skiplist_motivation_plot.py
```

### Reproduce Table 8 of the paper

- Running experiments
```bash
~/gpu-oversubscribed-ds-oopsla26$ bash benchmark_scripts/skiplist_scripts/keys_per_warp_study.sh
```
- Generate a consolidate csv file for traces
```bash
~/gpu-oversubscribed-ds-oopsla26$ python3 benchmark_scripts/skiplist_scripts/parse_kpw_results.py skiplist_results/kpw_study
```

- Output will be stored in the `table8.csv` file in `~/gpu-oversubscribed-ds-oopsla26`

### Reproduce Table 9 of the paper

- Running experiments
```bash
~/gpu-oversubscribed-ds-oopsla26$ bash benchmark_scripts/skiplist_scripts/thread_block_study.sh
```
- Generating consolidate csv file for traces
```bash
~/gpu-oversubscribed-ds-oopsla26$ python3 benchmark_scripts/skiplist_scripts/parse_thread_block_results.py skiplist_results/thread_block_study
```
- Output will be stored in the `table9.csv` file in `~/gpu-oversubscribed-ds-oopsla26`

### Reproduce Table 10 of the paper

- Running the experiments
```bash
~/gpu-oversubscribed-ds-oopsla26$ bash benchmark_scripts/skiplist_scripts/innersl_sensitivity_study.sh
```
- Generating the consolidated csv  file for traces
```bash
~/gpu-oversubscribed-ds-oopsla26$ python3 benchmark_scripts/skiplist_scripts/parse_innersl_sensitivity_results.py skiplist_results/innersl_sensitivity_study
```
- Output will be stored in the `table10.csv` file in `~/gpu-oversubscribed-ds-oopsla26`

### Reproduce fig 16 of the paper (Main contribution for skiplist)

- Execute the motivation script present in benchmark_scripts 
```bash
~/gpu-oversubscribed-ds-oopsla26$ bash benchmark_scripts/skiplist_scripts/fig16_script.sh
```

- Parse the log files to generate csv file, generates `fig16_study.csv` in path `~/gpu-oversubscribed-ds-oopsla26`
```bash
~/gpu-oversubscribed-ds-oopsla26$ python3 benchmark_scripts/skiplist_scripts/parse_fig16_results.py skiplist_results/fig16_study
```

- Generating figure 16 of the paper. The file `fig16.pdf` will be generated in the `figures_skiplist` folder
```bash
~/gpu-oversubscribed-ds-oopsla26$ python3 Graph_Plotting_Scripts/skiplist_fig16_plot.py
```

### Downloading data set for the metagenomic and K-mer applications

```bash

wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/635/GCF_000001635.27_GRCm39/GCF_000001635.27_GRCm39_genomic.fna.gz
gunzip -c GCF_000001635.27_GRCm39_genomic.fna.gz > skiplist_traces/GCF_000001635.27_GRCm39_genomic.fna

wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/002/285/GCF_000002285.3_CanFam3.1/GCF_000002285.3_CanFam3.1_genomic.fna.gz
gunzip -c GCF_000002285.3_CanFam3.1_genomic.fna.gz > skiplist_traces/GCF_000002285.3_CanFam3.1_genomic.fna

```

**NOTE: Fig 6b and 17 for skiplist uses the same real-world application**

- Execute the applicatons study script present in benchmark_scripts. Generate the data both for fig 6b and 17.
```bash
~/gpu-oversubscribed-ds-oopsla26$ bash benchmark_scripts/skiplist_scripts/applications_study.sh
```

### Scalability study of Metageonomic application(Fig 6b of the paper)

- Parse the log files to generate csv file, generates `fig_6b_study.csv` in path `~/gpu-oversubscribed-ds-oopsla26`
```bash
~/gpu-oversubscribed-ds-oopsla26$ python3 benchmark_scripts/skiplist_scripts/parse_fig6b_results.py skiplist_results/applications_study
```
- Generating figure 6b of the paper. The file `fig_6b.pdf` will be generated in the `figures_skiplist` folder
```bash
~/gpu-oversubscribed-ds-oopsla26$ python3 Graph_Plotting_Scripts/skiplist_fig6b_plot.py
```

### Study of real-world applications(Fig 17 (RHS) of the paper)

- Parse the log files to generate csv file, generates `fig_17_study.csv` in path `~/gpu-oversubscribed-ds-oopsla26`
```bash
~/gpu-oversubscribed-ds-oopsla26$ python3 benchmark_scripts/skiplist_scripts/parse_fig6b_results.py skiplist_results/applications_study
```
- Generating figure 17 (RHS) of the paper. The file `fig_17.pdf` will be generated in the `figures_skiplist` folder
```bash
~/gpu-oversubscribed-ds-oopsla26$ python3 Graph_Plotting_Scripts/skiplist_fig17_plot.py
```