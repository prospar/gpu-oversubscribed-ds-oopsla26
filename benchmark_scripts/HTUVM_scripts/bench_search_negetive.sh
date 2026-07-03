#! /bin/bash

set -e

operations=(
            5625000000
            7000000000
            6250000000
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
                outdir="./../results_HTUVM/search_negative/MI"
                ;;
            "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE.bin")
                outdir="./../results_HTUVM/search_negative/DU"
                ;;
            "insert_trace-400e7-100-add-20-dup-DENSE_REPEAT.bin")
                outdir="./../results_HTUVM/search_negative/DR"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE.bin")
                outdir="./../results_HTUVM/search_negative/SU"
                ;;
            "insert_trace-400e7-100-add-20-dup-SPARSE_REPEAT.bin")
                outdir="./../results_HTUVM/search_negative/SR"
                ;;
            "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE_1e9_Clusters.bin")
                outdir="./../results_HTUVM/search_negative/DUL"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_5e8_Random_Clusters.bin")
                outdir="./../results_HTUVM/search_negative/SUR"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_ZigZag.bin")
                outdir="./../results_HTUVM/search_negative/ZZ"
                ;;
        esac
        mkdir -p "$outdir"
        if [ "$ops" -eq 7000000000 ]; then
            add_ops=3000000000
        else
            add_ops=2500000000
        fi
        ./uvm-opt.out -ops="$ops" -add="$add_ops" -rem=0 -fil=1 -rns=1 -tra="$file" -trf="$file" -gbs=100000000 > "${outdir}/${ops}.log"
    done
done
