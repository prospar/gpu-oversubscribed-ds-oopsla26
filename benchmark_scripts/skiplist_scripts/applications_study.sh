#!/bin/bash

CURRENT_DIR=$PWD
BIN_DIR="$CURRENT_DIR/bin"
skiplist_results_dir="$CURRENT_DIR/skiplist_results"
expr_dir="applications_study"

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

echo "Experiments for thread block study configuration: $expr_dir runs: $runs"

# ovr %         10    30    50
# reservation  "1GB" "3GB" "5GB"

bench_list=( "sluvm_kmer" "sluvm_classifier" "slovs_kmer" "slovs_classifier" )


echo "Starting applications experiment"
for bench in "${bench_list[@]}"
do
    if [ -d $skiplist_results_dir/$expr_dir/$bench ]; then
        echo "Log directory for skiplist experiments exists"
    else
        echo "Creating directory for skiplist $expr_dir/$bench experiments"
        mkdir -p $skiplist_results_dir/$expr_dir/$bench
    fi
done

$BIN_DIR/sluvm_classifier.out -ovr=1 -ovl=1 -blk=16384 -siz=512 -rns=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/sluvm_classifier/output_ovr10.log 2>&1
$BIN_DIR/sluvm_classifier.out -ovr=1 -ovl=3 -blk=16384 -siz=512 -rns=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/sluvm_classifier/output_ovr30.log 2>&1
$BIN_DIR/sluvm_classifier.out -ovr=1 -ovl=5 -blk=16384 -siz=512 -rns=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/sluvm_classifier/output_ovr50.log 2>&1
$BIN_DIR/slovs_classifier.out -ovr=1 -ovl=1 -rng=21 -blk=16384 -siz=512 -rns=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/slovs_classifier/output_ovr10.log 2>&1
$BIN_DIR/slovs_classifier.out -ovr=1 -ovl=3 -rng=21 -blk=16384 -siz=512 -rns=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/slovs_classifier/output_ovr30.log 2>&1
$BIN_DIR/slovs_classifier.out -ovr=1 -ovl=5 -rng=21 -blk=16384 -siz=512 -rns=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/slovs_classifier/output_ovr50.log 2>&1

$BIN_DIR/sluvm_kmer.out -ovr=1 -ovl=1 -blk=15625000 -siz=512 -rns=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/sluvm_kmer/output_ovr10.log 2>&1
$BIN_DIR/sluvm_kmer.out -ovr=1 -ovl=3 -blk=15625000 -siz=512 -rns=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/sluvm_kmer/output_ovr30.log 2>&1
$BIN_DIR/sluvm_kmer.out -ovr=1 -ovl=5 -blk=15625000 -siz=512 -rns=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/sluvm_kmer/output_ovr50.log 2>&1
$BIN_DIR/slovs_kmer.out -ovr=1 -ovl=1 -rng=21 -blk=15625000 -siz=512 -rns=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/slovs_kmer/output_ovr10.log 2>&1
$BIN_DIR/slovs_kmer.out -ovr=1 -ovl=3 -rng=21 -blk=15625000 -siz=512 -rns=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/slovs_kmer/output_ovr30.log 2>&1
$BIN_DIR/slovs_kmer.out -ovr=1 -ovl=5 -rng=21 -blk=15625000 -siz=512 -rns=1 -gbs=250000000 > $skiplist_results_dir/$expr_dir/slovs_kmer/output_ovr50.log 2>&1
echo "Experiments completed for applications"
