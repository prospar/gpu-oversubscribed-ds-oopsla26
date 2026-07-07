# gpu-oversubscribed-ds-oopsla26

<!-- For GPH -->

# For GPH

To simualte oversubscription scenarios for GPH update the value in line 72 in the file geph_exp.cuh(gph_opensource_copy_original/perf/geph_exp.cuh)

Value       Oversubscription
12.8        25%
13.33       50%
13.72       75%
14          100%

Simialry to change trace types, update the absolute path of trace files 149-150 and 156-157 in the file perf-final-uitls.cuh(gph_opensource_copy_original/perf/perf-final-uitls.cuh). The traces for GPH are provided with the directory and so there is no need to regenerate them.

To build and run GPH:
1) Open a terminal in the gph main directory.
2) Run the command "cmake --build build"
3) Next run the command "cd build/perf"
4) Finally run the command "./perf"

After updating the trace file path or memory reservation the above commands needs to be ran again.