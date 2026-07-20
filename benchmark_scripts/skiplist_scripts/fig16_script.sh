#!/bin/bash

CURRENT_DIR=$PWD
BIN_DIR="$CURRENT_DIR/bin"
skiplist_results_dir="$CURRENT_DIR/skiplist_results"
expr_dir="fig16_study"

if [[ -v SL_TRACE_ROOT ]]; then
    echo "The path for root dir of traces exists."
else
    echo "Set the env variable SL_TRACE_ROOT with path of traces"
    exit 1
fi

if [ -d $skiplist_results_dir ]; then
    echo "Directory for skiplist experiments exists"
else
    echo "Creating directory for skiplist experiments" 
    mkdir ${skiplist_results_dir} 
fi

if [ -d $skiplist_results_dir/$expr_dir ]; then
    echo "Log directory for thread-block experiments exists"
else
    echo "Creating directory for thread block $expr_dir experiments" 
    mkdir $skiplist_results_dir/$expr_dir
fi


runs=1

if [ $2 ]; then
    runs=$2
else
    echo "Default 1 runs"
    echo $runs
fi

if [ $expr_dir ]; then
    echo "Results in $expr_dir "
else
    echo "Specify the directory name as first argument to store results"
fi

echo "Experiments for fig 16 configuration: $expr_dir runs: $runs"

# trace_type=( "MonotonicIncrease" "SparseUnique" "DenseUnique" )
trace_type=( "SparseUnique" )

# ovr %          0             20          40           60            80            100
# input size "2500000000" "3000000000" "3500000000" "4000000000" "4500000000"  "5000000000"

num_ops=( "2500000000" "3000000000" "3500000000" "4000000000" "4500000000"  "5000000000" )

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

    $BIN_DIR/sl-uvm-sort.out -ops=$size -add=$oper -rem=0 -tra="insert_trace-25e7-800e7-50-add-0-rem-50-find-no-dup-DENSE_UNIQUE.bin" -trf="search_trace-25e7-800e7-50-add-0-rem-50-find-no-dup-no-absent-DENSE_UNIQUE.bin" -trr="" -blk=16384 -siz=512 -rns=1 -gbs=250000000 -kpw=300 -wtw=1 > $skiplist_results_dir/$expr_dir/sl-uvm-sort/$size/DenseUnique/output.log 2>&1
    $BIN_DIR/sl-uvm-sort.out -ops=$size -add=$oper -rem=0 -tra="insert_trace-25e7-800e7-50-add-0-rem-50-find-no-dup-SPARSE_UNIQUE.bin" -trf="search_trace-25e7-800e7-50-add-0-rem-50-find-no-dup-no-absent-SPARSE_UNIQUE.bin" -trr="" -blk=16384 -siz=512 -rns=1 -gbs=250000000 -kpw=300 -wtw=1 > $skiplist_results_dir/$expr_dir/sl-uvm-sort/$size/SparseUnique/output.log 2>&1
    $BIN_DIR/sl-uvm-sort.out -ops=$size -add=$oper -rem=0 -tra="insert_trace-25e7-400e7-100-add-0-rem-0-find-no-dup-MONOTONIC_INCREASE.bin" -trf="insert_trace-25e7-400e7-100-add-0-rem-0-find-no-dup-MONOTONIC_INCREASE.bin" -trr="" -blk=16384 -siz=512 -rns=1 -gbs=250000000 -kpw=300 -wtw=1 > $skiplist_results_dir/$expr_dir/sl-uvm-sort/$size/MonotonicIncrease/output.log 2>&1
    $BIN_DIR/sl-ovs-sort.out -ops=$size -add=$oper -rem=0 -tra="insert_trace-25e7-800e7-50-add-0-rem-50-find-no-dup-DENSE_UNIQUE.bin" -trf="search_trace-25e7-800e7-50-add-0-rem-50-find-no-dup-no-absent-DENSE_UNIQUE.bin" -trr="" -blk=16384 -siz=512 -rns=1 -gbs=250000000 -kpw=180 -wtw=1 -rng=21 > $skiplist_results_dir/$expr_dir/sl-ovs-sort/$size/DenseUnique/output.log 2>&1
    $BIN_DIR/sl-ovs-sort.out -ops=$size -add=$oper -rem=0 -tra="insert_trace-25e7-800e7-50-add-0-rem-50-find-no-dup-SPARSE_UNIQUE.bin" -trf="search_trace-25e7-800e7-50-add-0-rem-50-find-no-dup-no-absent-SPARSE_UNIQUE.bin" -trr="" -blk=16384 -siz=512 -rns=1 -gbs=250000000 -kpw=180 -wtw=1 -rng=21 > $skiplist_results_dir/$expr_dir/sl-ovs-sort/$size/SparseUnique/output.log 2>&1
    $BIN_DIR/sl-ovs-sort.out -ops=$size -add=$oper -rem=0 -tra="insert_trace-25e7-400e7-100-add-0-rem-0-find-no-dup-MONOTONIC_INCREASE.bin" -trf="insert_trace-25e7-400e7-100-add-0-rem-0-find-no-dup-MONOTONIC_INCREASE.bin" -trr="" -blk=16384 -siz=512 -rns=1 -gbs=250000000 -kpw=180 -wtw=1 -rng=21 > $skiplist_results_dir/$expr_dir/sl-ovs-sort/$size/MonotonicIncrease/output.log 2>&1
        
    echo "Experiments completed for input set $size"
    
done
echo "Completed the experiments set with $expr_dir of skiplist"
