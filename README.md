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

## Environment and Machine Details:

- The system configuration used for the experiments and scritps: 

|               |                         |          |                                 |
| :------------ | :---------------------- | :------- | :------------------------------ |
| GPU           | NVIDIA Quadro RTX 5000  | OS       | Ubuntu 22.04.1                 |
| GPU Memory    | 16GB                    | Kernel   | Linux 6.8.0-59-generic          |
| Driver Version| 580.76.05               | Compiler | nvcc -std=c++17 -arch=sm_75 -O3 |
| Graphic Bus   | PCI Express 3.0 x 16    | Thrust Version |  2.8.2           |


#### Required library version:

- Verify the python libraries version by running the script:
```bash
python3 benchmark_scripts/skiplist_scripts/verify_python_library.py
```

The output should be following
```
Matplotlib version: 3.9.3
NumPy version: 2.1.3
Pandas version: 2.2.3
```

### Sanity check:
- Run the validation script to create directory structures
```bash
bash benchmark_scripts/skiplist_scripts/validation_script.sh
```
- Add an environment variable in the `.bashrc`
```bash
export SL_TRACE_ROOT=<path of gpu-oversubscribed-ds-oopsls26 directory>/skiplist_traces
```
### Build the binaries:
- Run the build binary script
```
bash benchmark_scripts/skiplist_scripts/build_binary.sh
```

### Kick-the-tire:
```bash
bash benchmark_scripts/skiplist_scripts/kick_the_tire_script.sh
```

### Generating the synthetic traces for full set of experiments:
```bash
bash tracegen_scripts/trace_script_skiplist.sh
```

### Downloading the traces for real-world application
```bash
bash tracegen_scripts/application_traces.sh
```

### Motivation Figure (figure 4(c) in the paper)


**Warning: Runtime of motivation results with sparse traces extends into hours for insert and search with oversubcription**

_The script runs only monotonic trace in default setting to complete in reasonable time, uncomment line 91 in the `motivation\_study.sh`to collect result for sparse traces_

- Execute the script for figure 4c present in benchmark_scripts 
```bash
bash benchmark_scripts/skiplist_scripts/fig4c_study.sh
```

- Parse the log files to generate csv file, generates `fig4c_study_skiplist.csv` in path `~/gpu-oversubscribed-ds-oopsla26/figures_skiplist`
```bash
python3 benchmark_scripts/skiplist_scripts/parse_fig4c_skiplist_results.py skiplist_results/fig4c_study
```
- Generating figure 4c of the paper. The file `fig4_c.pdf` will be generated in the `~/gpu-oversubscribed-ds-oopsla26/figures_skiplist` folder
```bash
python3 Graph_Plotting_Scripts/skiplist_fig4c_plot.py
```

### Reproduce Table 8 of the paper

- Running experiments
```bash
bash benchmark_scripts/skiplist_scripts/table8_study.sh
```
- Generate a consolidate csv file for traces
```bash
python3 benchmark_scripts/skiplist_scripts/parse_table8_results.py skiplist_results/table8_study
```

- Output will be stored in the `table8.csv` file in `~/gpu-oversubscribed-ds-oopsla26/figures_skiplist`

### Reproduce Table 9 of the paper

- Running experiments
```bash
bash benchmark_scripts/skiplist_scripts/table9_study.sh
```
- Generating consolidate csv file for traces
```bash
python3 benchmark_scripts/skiplist_scripts/parse_table9_results.py skiplist_results/table9_study
```
- Output will be stored in the `table9.csv` file in `~/gpu-oversubscribed-ds-oopsla26/figures_skiplist`

### Reproduce Table 10 of the paper

- Running the experiments
```bash
bash benchmark_scripts/skiplist_scripts/table10_study.sh
```
- Generating the consolidated csv  file for traces
```bash
python3 benchmark_scripts/skiplist_scripts/parse_table10_results.py skiplist_results/table10_study
```
- Output will be stored in the `table10.csv` file in `~/gpu-oversubscribed-ds-oopsla26/figures_skiplist`

### Reproduce fig 16 of the paper (Main contribution for skiplist)

- Execute the motivation script present in benchmark_scripts 
```bash
bash benchmark_scripts/skiplist_scripts/fig16_script.sh
```

- Parse the log files to generate csv file, generates `fig16_study.csv` in path `~/gpu-oversubscribed-ds-oopsla26/figures_skiplist`
```bash
python3 benchmark_scripts/skiplist_scripts/parse_fig16_results.py skiplist_results/fig16_study
```

- Generating figure 16 of the paper. The file `fig16.pdf` will be generated in the `~/gpu-oversubscribed-ds-oopsla26/figures_skiplist` folder
```bash
python3 Graph_Plotting_Scripts/skiplist_fig16_plot.py
```

**NOTE: Fig 6b and 17 for skiplist uses the same real-world application**

- Execute the applicatons study script present in benchmark_scripts. Generate the data both for fig 6b and 17.
```bash
bash benchmark_scripts/skiplist_scripts/applications_study.sh
```

### Scalability study of Metageonomic application(Fig 6b of the paper)

- Parse the log files to generate csv file, generates `fig6b_study.csv` in path `~/gpu-oversubscribed-ds-oopsla26/figures_skiplist`
```bash
python3 benchmark_scripts/skiplist_scripts/parse_fig6b_results.py skiplist_results/applications_study
```
- Generating figure 6b of the paper. The file `fig_6b.pdf` will be generated in the `~/gpu-oversubscribed-ds-oopsla26/figures_skiplist` folder
```bash
python3 Graph_Plotting_Scripts/skiplist_fig6b_plot.py
```

### Study of real-world applications(Fig 17 (RHS) of the paper)

- Parse the log files to generate csv file, generates `fig17_study.csv` in path `~/gpu-oversubscribed-ds-oopsla26/figures_skiplist`
```bash
python3 benchmark_scripts/skiplist_scripts/parse_fig17_results.py skiplist_results/applications_study
```

- Generating figure 17 (RHS) of the paper. The file `fig_17.pdf` will be generated in the `~/gpu-oversubscribed-ds-oopsla26/figures_skiplist` directory
```bash
python3 Graph_Plotting_Scripts/skiplist_fig17_plot.py
```