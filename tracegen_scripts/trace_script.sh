#!/bin/bash

echo "Current directory $PWD"
CURRENT_DIR=$PWD
BIN_DIR="$CURRENT_DIR/bin"
mkdir -p "$CURRENT_DIR/skiplist_traces"
export SL_TRACE_ROOT="$CURRENT_DIR/skiplist_traces"
# for creating 
echo $SL_TRACE_ROOT

make trace-gen-25e7
echo "generating monotonic trace"
$BIN_DIR/trace-gen-25e7.out -ops=4000000000 -add=100 -rem=0 -dpf=0 -dpa=0 -dpr=0 -npd=0 -nps=0 -npd=0 -tpt=MONOTONIC_INCREASE
echo "generating dense unique trace"
$BIN_DIR/trace-gen-25e7.out -ops=8000000000 -add=50 -rem=0 -dpf=0 -dpa=0 -dpr=0 -npd=0 -nps=0 -npd=0 -tpt=DENSE_UNIQUE
echo "generating sparse unique trace"
$BIN_DIR/trace-gen-25e7.out -ops=8000000000 -add=50 -rem=0 -dpf=0 -dpa=0 -dpr=0 -npd=0 -nps=0 -npd=0 -tpt=SPARSE_UNIQUE


python3 tracegen_MI.py
python3 tracegen_DR.py
python3 tracegen_DU.py
python3 tracegen_SU.py
python3 tracegen_SR.py
python3 tracegen_DUL.py
python3 tracegen_SUR.py
python3 tracegen_ZZ.py
python3 tracegen_DU_GPH.py
python3 tracegen_SU_GPH.py
python3 tracegen_MI_GPH.py
