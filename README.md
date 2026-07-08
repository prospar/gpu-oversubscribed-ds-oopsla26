# gpu-oversubscribed-ds-oopsla26

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