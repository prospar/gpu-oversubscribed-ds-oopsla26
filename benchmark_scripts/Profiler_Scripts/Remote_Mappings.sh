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
                outdir="./../results_RM/insert_htuvm/MI"
                ;;
            "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE.bin")
                outdir="./../results_RM/insert_htuvm/DU"
                ;;
            "insert_trace-400e7-100-add-20-dup-DENSE_REPEAT.bin")
                outdir="./../results_RM/insert_htuvm/DR"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE.bin")
                outdir="./../results_RM/insert_htuvm/SU"
                ;;
            "insert_trace-400e7-100-add-20-dup-SPARSE_REPEAT.bin")
                outdir="./../results_RM/insert_htuvm/SR"
                ;;
            "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE_1e9_Clusters.bin")
                outdir="./../results_RM/insert_htuvm/DUL"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_5e8_Random_Clusters.bin")
                outdir="./../results_RM/insert_htuvm/SUR"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_ZigZag.bin")
                outdir="./../results_RM/insert_htuvm/ZZ"
                ;;
        esac
        mkdir -p "$outdir"
        base=2000000000
        oversub=$(( (ops - base) * 100 / base ))
        nvprof ./uvm-opt.out -ops="$ops" -add="$ops" -fil=1 -rem=0 -rns=1 -tra="$file" -gbs=100000000 -rng=1048576 > "${outdir}/${oversub}.log"
    done
done

for ops in "${operations[@]}"
do
    for file in "${files[@]}"
    do
        case "$file" in
            "insert_trace-400e7-100-add-no-dup-MONOTONIC_INCREASE.bin")
                outdir="./../results_RM/insert_htovs/MI"
                ;;
            "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE.bin")
                outdir="./../results_RM/insert_htovs/DU"
                ;;
            "insert_trace-400e7-100-add-20-dup-DENSE_REPEAT.bin")
                outdir="./../results_RM/insert_htovs/DR"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE.bin")
                outdir="./../results_RM/insert_htovs/SU"
                ;;
            "insert_trace-400e7-100-add-20-dup-SPARSE_REPEAT.bin")
                outdir="./../results_RM/insert_htovs/SR"
                ;;
            "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE_1e9_Clusters.bin")
                outdir="./../results_RM/insert_htovs/DUL"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_5e8_Random_Clusters.bin")
                outdir="./../results_RM/insert_htovs/SUR"
                ;;
            "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_ZigZag.bin")
                outdir="./../results_RM/insert_htovs/ZZ"
                ;;
        esac
        mkdir -p "$outdir"
        base=2000000000
        oversub=$(( (ops - base) * 100 / base ))
        nvprof ./htovs-opt.out -ops="$ops" -add="$ops" -fil=1 -rem=0 -rns=1 -tra="$file" -gbs=1000000000 -rng=1048576 > "${outdir}/${oversub}.log"
    done
done
