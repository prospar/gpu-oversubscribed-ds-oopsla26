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
                outdir="./../results_HTOVS/search_negative/MI"
                ;;
            "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE.bin")
                outdir="./../results_HTOVS/search_negative/DU"
                ;;
            "insert_trace-400e7-100-add-20-dup-DENSE_REPEAT.bin")
                outdir="./../results_HTOVS/search_negative/DR"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE.bin")
                outdir="./../results_HTOVS/search_negative/SU"
                ;;
            "insert_trace-400e7-100-add-20-dup-SPARSE_REPEAT.bin")
                outdir="./../results_HTOVS/search_negative/SR"
                ;;
            "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE_1e9_Clusters.bin")
                outdir="./../results_HTOVS/search_negative/DUL"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_5e8_Random_Clusters.bin")
                outdir="./../results_HTOVS/search_negative/SUR"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_ZigZag.bin")
                outdir="./../results_HTOVS/search_negative/ZZ"
                ;;
        esac
        mkdir -p "$outdir"
        if [ "$ops" -eq 7000000000 ]; then
            add_ops=3000000000
        else
            add_ops=2500000000
        fi
        base_ops=$((ops - add_ops))
        num=$((base_ops - add_ops))
        den=$base_ops

        a=$num
        b=$den
        while [ $b -ne 0 ]; do
            t=$b
            b=$((a % b))
            a=$t
        done
        gcd=$a

        num=$((num / gcd))
        den=$((den / gcd))
        ./htovs-opt.out -ops="$ops" -add="$add_ops" -rem=0 -fil=1 -rns=1 -tra="$file" -trf="$file" -gbs=1000000000 -rng=1048576 > "${outdir}/${num}_${den}.log"
    done
done
