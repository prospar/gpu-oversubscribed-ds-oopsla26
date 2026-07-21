#!/bin/bash
echo "Current directory $PWD"
CURRENT_DIR=$PWD
BIN_DIR="$CURRENT_DIR/bin"
skiplist_results_dir="$CURRENT_DIR/skiplist_results"
expr_dir="kick_the_tire"

mkdir -p "$CURRENT_DIR/skiplist_traces"

# must add export SL_TRACE_ROOT="$CURRENT_DIR/skiplist_traces" in bashrc
export SL_TRACE_ROOT="$CURRENT_DIR/skiplist_traces"
echo $SL_TRACE_ROOT

if [[ -v SL_TRACE_ROOT ]]; then
    echo "The path for root dir of traces exists."
else
    echo "Set the env variable SL_TRACE_ROOT with path of traces"
    exit 1
fi

# trace generation testing
make trace-gen-1e7
$BIN_DIR/trace-gen-1e7.out -ops=50000000 -add=100 -rem=0 -dpf=0 -dpa=0 -dpr=0 -npd=0 -nps=0 -npd=0 -tpt=MONOTONIC_INCREASE
$BIN_DIR/trace-gen-1e7.out -ops=100000000 -add=50 -rem=0 -dpf=0 -dpa=0 -dpr=0 -npd=0 -nps=0 -npd=0 -tpt=DENSE_UNIQUE
# $BIN_DIR/trace-gen-1e7.out -ops=100000000 -add=50 -rem=0 -dpf=0 -dpa=0 -dpr=0 -npd=0 -nps=0 -npd=0 -tpt=SPARSE_UNIQUE

# testing make
make sl-uvm-sort
make sl-ovs-sort

if [ -d $skiplist_results_dir ]; then
    echo "Directory for skiplist experiments exists"
else
    echo "Creating directory for skiplist experiments" 
    mkdir -p ${skiplist_results_dir} 
fi


if [ -d $skiplist_results_dir/$expr_dir ]; then
    echo "Log directory for thread-block experiments exists"
else
    echo "Creating directory for thread block $expr_dir experiments" 
    mkdir $skiplist_results_dir/$expr_dir
fi

if [ $expr_dir ]; then
    echo "Results in $expr_dir "
else
    echo "Specify the directory name as first argument to store results"
fi


####### LAUNCH EXP #####################
runs=1

echo "Launching experiments for kick-the-tire: $expr_dir runs: $runs"

trace_type=( "MonotonicIncrease" "DenseUnique" )

num_ops=( "20000000" "40000000" "60000000" "80000000" "100000000" )

bench_list=( "sl-uvm-sort" "sl-ovs-sort" )

for size in "${num_ops[@]}"
do
    echo "Starting skiplist gfsl experiment for $size"
    for bench in "${bench_list[@]}"
    do
        if [ -d $skiplist_results_dir/$expr_dir/$bench ]; then
            echo "Log directory for skiplist experiments exists"
        else
            echo "Creating directory for skiplist $expr_dir experiments"
            mkdir $skiplist_results_dir/$expr_dir/$bench
        fi
        if [ -d $skiplist_results_dir/$expr_dir/$bench/$size ]; then
            echo "Log directory for input $size exists"
        else
            echo "Creating directory for skiplist $expr_dir/$bench/$size experiments" 
            mkdir $skiplist_results_dir/$expr_dir/$bench/$size
        fi
        for trace in "${trace_type[@]}"
        do
            if [ -d $skiplist_results_dir/$expr_dir/$bench/$size/$trace ]; then
                echo "Log directory for skiplist input exists"
            else
                echo "Creating directory for skiplist $expr_dir/$bench/$size/$trace"
                mkdir $skiplist_results_dir/$expr_dir/$bench/$size/$trace
            fi
        done
    done
    div_factor=2
    oper=$((size / div_factor))

    $BIN_DIR/sl-uvm-sort.out -ops=$size -add=$oper -rem=0 -tra="insert_trace-1e7-10e7-50-add-0-rem-50-find-no-dup-DENSE_UNIQUE.bin" -trf="search_trace-1e7-10e7-50-add-0-rem-50-find-no-dup-no-absent-DENSE_UNIQUE.bin" -trr="" -blk=16384 -siz=512 -rns=1 -gbs=250000000 -kpw=300 -wtw=1 > $skiplist_results_dir/$expr_dir/sl-uvm-sort/$size/DenseUnique/output.log 2>&1
    $BIN_DIR/sl-uvm-sort.out -ops=$size -add=$oper -rem=0 -tra="insert_trace-1e7-5e7-100-add-0-rem-0-find-no-dup-MONOTONIC_INCREASE.bin" -trf="insert_trace-1e7-5e7-100-add-0-rem-0-find-no-dup-MONOTONIC_INCREASE.bin" -trr="" -blk=16384 -siz=512 -rns=1 -gbs=250000000 -kpw=300 -wtw=1 > $skiplist_results_dir/$expr_dir/sl-uvm-sort/$size/MonotonicIncrease/output.log 2>&1
    $BIN_DIR/sl-ovs-sort.out -ops=$size -add=$oper -rem=0 -tra="insert_trace-1e7-10e7-50-add-0-rem-50-find-no-dup-DENSE_UNIQUE.bin" -trf="search_trace-1e7-10e7-50-add-0-rem-50-find-no-dup-no-absent-DENSE_UNIQUE.bin" -trr="" -blk=16384 -siz=512 -rns=1 -gbs=250000000 -kpw=180 -wtw=1 -rng=21 > $skiplist_results_dir/$expr_dir/sl-ovs-sort/$size/DenseUnique/output.log 2>&1
    $BIN_DIR/sl-ovs-sort.out -ops=$size -add=$oper -rem=0 -tra="insert_trace-1e7-5e7-100-add-0-rem-0-find-no-dup-MONOTONIC_INCREASE.bin" -trf="insert_trace-1e7-5e7-100-add-0-rem-0-find-no-dup-MONOTONIC_INCREASE.bin" -trr="" -blk=16384 -siz=512 -rns=1 -gbs=250000000 -kpw=180 -wtw=1 -rng=21 > $skiplist_results_dir/$expr_dir/sl-ovs-sort/$size/MonotonicIncrease/output.log 2>&1

    echo "Experiments completed for input set $size"
    
done
echo "Completed the kick-the-tire experiments of skiplist"


######### PARSE RESULT #############
python3 benchmark_scripts/skiplist_scripts/parse_ktt_results.py $skiplist_results_dir/$expr_dir

######### PLOT BAR CHART ##########

python3 Graph_Plotting_Scripts/skiplist_ktt_plot.py

### plot saved as figures_skiplist/kick_the_tire.pdf

echo "Kick-the-Tire Successful, Check the kick_the_tire.pdf fig in figures_skiplist directory"