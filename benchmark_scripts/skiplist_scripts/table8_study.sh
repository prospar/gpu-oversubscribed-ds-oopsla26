#!/bin/bash

CURRENT_DIR=$PWD
BIN_DIR="$CURRENT_DIR/bin"
skiplist_results_dir="$CURRENT_DIR/skiplist_results"
expr_dir="table8_study"

if [[ -v SL_TRACE_ROOT ]]; then
    echo "The path for root dir of traces exists."
else
    echo "Set the env variable SL_TRACE_ROOT with path of traces"
    exit 1
fi

if [ -d $skiplist_results_dir ]; then
    echo "Log directory for uvm experiments exists"
else
    echo "Creating directory for UVM experiments" 
    mkdir ${skiplist_results_dir} 
fi

if [ -d $skiplist_results_dir/$expr_dir ]; then
    echo "Log directory for skiplist experiments exists"
else
    echo "Creating directory for skiplist $expr_dir experiments" 
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
    echo "Config ${1}"
else
    echo "Specify the configuration name"
fi

echo "Experiments with configuration: $expr_dir runs: $runs"

trace_type=( "DenseUnique" "MonotonicIncrease" )

num_ops=( "4000000000" ) 

bench_list=( "sl-uvm-kpw" )

# key_list=( "1" "15" "30" "60" "120" "150" "180" "210" "240" "270" "300" "330" "360" "390") 
key_list=( "1" "30" "60" "120" "150" "180" "210" "240" "270" "300" "330" "360" ) 

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
        div_factor=2
        oper=$((size / div_factor))
        for keys in "${key_list[@]}"
        do
            $BIN_DIR/$bench.out -ops=$oper -add=$oper -rem=0 -tra="insert_trace-25e7-800e7-50-add-0-rem-50-find-no-dup-DENSE_UNIQUE.bin" -trf="" -trr="" -blk=15625000 -siz=512 -rns=1 -kpw=$keys -wtw=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/$bench/$size/DenseUnique/output-kpw$keys.log 2>&1
            $BIN_DIR/$bench.out -ops=$oper -add=$oper -rem=0 -tra="insert_trace-25e7-400e7-100-add-0-rem-0-find-no-dup-MONOTONIC_INCREASE.bin" -trf="" -trr="" -blk=15625000 -siz=512 -rns=1 -kpw=$keys -wtw=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/$bench/$size/MonotonicIncrease/output-kpw$keys.log 2>&1
        done
    done
    echo "Experiments completed for input set $size"
    
done
echo "Completed the experiments set with $expr_dir of skiplist"
