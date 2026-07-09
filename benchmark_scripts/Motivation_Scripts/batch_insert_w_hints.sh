#! /bin/bash

set -e

operations=(
            1500000000
            2000000000 
            2500000000 
            3000000000 
            3500000000 
            4000000000
           )
files=(
       "insert_trace-400e7-100-add-no-dup-MONOTONIC_INCREASE.bin" 
       "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE.bin"
       )


cd ./../../bin/
for ops in "${operations[@]}"
do
    for file in "${files[@]}"
    do
        if [[ "$file" == "insert_trace-400e7-100-add-no-dup-MONOTONIC_INCREASE.bin" ]]; then
            outdir="./../results_Motivation_w_hints/insert/MI"
        else
            outdir="./../results_Motivation_w_hints/insert/SU"
        fi

        mkdir -p "$outdir"
        ./uvm-opt.out -ops="$ops" -add="$ops" -fil=1 -rem=0 -rns=1 -tra="$file" -gbs=100000000 > "${outdir}/${ops}.log"
    done
done
