#!/bin/bash
# files contains steps to build skiplist binaries

CURRENT_DIR=$PWD
BIN_DIR="$CURRENT_DIR/bin"
skiplist_results_dir="$CURRENT_DIR/skiplist_results"
skiplist_figs_dir="$CURRENT_DIR/figures_skiplist"
skiplist_scripts_dir="$CURRENT_DIR/benchmark_scripts/skiplist_scripts"
skiplist_traces_dir="$CURRENT_DIR/skiplist_traces"

# check if skiplist scripts exists
if [ -d $skiplist_scripts_dir ]; then
    echo "Directory with scripts to conduct skip list experiments exists"
else
    echo "Scripts to run skip lists experiment does not exists"
fi

# check trhe directory to store results
if [ -d $skiplist_results_dir ]; then
    echo "The results dir for skip list exists"
else
    echo "Creating directory to store intermediate results" 
    mkdir -p ${skiplist_results_dir} 
fi

# check the directory to store figures
if [ -d $skiplist_figs_dir ]; then
    echo "The dir to store skip list figures exists"
else
    echo "Creating directory to store processed figure and results" 
    mkdir -p ${skiplist_figs_dir} 
fi

if [ -d $skiplist_traces_dir ]; then
    echo "Directory for skip list binaries exists"
else
    echo "Creating directory for skiplist binaries: $skiplist_traces_dir" 
    mkdir -p $skiplist_traces_dir
    export SL_TRACE_ROOT=$skiplist_trace_dir
    echo $SL_TRACE_ROOT
fi


if [ -d $BIN_DIR ]; then
    echo "Directory for skip list binaries exists"
else
    echo "Creating directory for skiplist binaries: $BIN_DIR" 
    mkdir -p $BIN_DIR
fi

if command -v gunzip >/dev/null 2>&1; then
    echo "gunzip is installed"
else
    echo "gunzip is NOT installed"
fi


echo "Directory structures is valid, can launch the kick-tire-script"