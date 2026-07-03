#! /bin/bash

set -e

operations=(
            2000000000 
            2500000000 
            3000000000 
            3500000000 
            4000000000
           )
files=(
       "insert_trace-400e7-100-add-no-dup-MONOTONIC_INCREASE.bin" 
       "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE.bin" 
       "insert_trace-400e7-100-add-20-dup-DENSE_REPEAT.bin"
       "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE.bin"
       "insert_trace-400e7-100-add-20-dup-SPARSE_REPEAT.bin"
       "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE_1e9_Clusters.bin"
       "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_5e8_Random_Clusters.bin"
       "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_ZigZag.bin"
       )


cd ./../../bin/
for ops in "${operations[@]}"
do
    for file in "${files[@]}"
    do
        case "$file" in
            "insert_trace-400e7-100-add-no-dup-MONOTONIC_INCREASE.bin")
                outdir="./../results_HTOVS/deletes/MI"
                ;;
            "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE.bin")
                outdir="./../results_HTOVS/deletes/DU"
                ;;
            "insert_trace-400e7-100-add-20-dup-DENSE_REPEAT.bin")
                outdir="./../results_HTOVS/deletes/DR"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE.bin")
                outdir="./../results_HTOVS/deletes/SU"
                ;;
            "insert_trace-400e7-100-add-20-dup-SPARSE_REPEAT.bin")
                outdir="./../results_HTOVS/deletes/SR"
                ;;
            "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE_1e9_Clusters.bin")
                outdir="./../results_HTOVS/deletes/DUL"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_5e8_Random_Clusters.bin")
                outdir="./../results_HTOVS/deletes/SUR"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_ZigZag.bin")
                outdir="./../results_HTOVS/deletes/ZZ"
                ;;
        esac
        mkdir -p "$outdir"
        total_ops=$((2 * ops))
        rem_ops=$((total_ops - ops))
        ./htovs-opt.out -ops="$total_ops" -add="$ops" -rem="$rem_ops" -fil=1 -rns=1 -tra="$file" -trr="$file" -gbs=1000000000 -rng=1048576 > "${outdir}/${ops}.log"
    done
done
