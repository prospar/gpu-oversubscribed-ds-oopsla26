#!/bin/bash
set -euo pipefail


EXECUTABLE=./cuco-insert.out
TRACE_DIR=/data/heterods-trace


cd ./../../bin/
operations=(
    2000000000
    # 2500000000
    # 3000000000
    # 3500000000
    # 4000000000
)

files=(
    # "insert_trace-400e7-100-add-20-dup-DENSE_REPEAT.bin"
    # "insert_trace-400e7-100-add-no-dup-MONOTONIC_INCREASE.bin"
    # "insert_trace-400e7-100-add-20-dup-SPARSE_REPEAT.bin"
    # "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE_1e9_Clusters.bin"
    # "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_5e8_Random_Clusters.bin"
    # "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_ZigZag.bin"
    # "insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE.bin"
    "insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE.bin"
)



for file in "${files[@]}"; do

    case "$file" in
        insert_trace-400e7-100-add-20-dup-DENSE_REPEAT.bin)
            outdir="./../results_CUCO/insert/DR"
            ;;
        insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE.bin)
            outdir="./../results_CUCO/insert/DU"
            ;;
        insert_trace-400e7-100-add-no-dup-MONOTONIC_INCREASE.bin)
            outdir="./../results_CUCO/insert/MI"
            ;;
        insert_trace-400e7-100-add-no-dup-DENSE_UNIQUE_1e9_Clusters.bin)
            outdir="./../results_CUCO/insert/DUL"
            ;;
        insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_5e8_Random_Clusters.bin)
            outdir="./../results_CUCO/insert/SUR"
            ;;
        insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE_ZigZag.bin)
            outdir="./../results_CUCO/insert/ZZ"
            ;;
        insert_trace-400e7-100-add-no-dup-SPARSE_UNIQUE.bin)
        outdir="./../results_CUCO/insert/SU"
            ;;
        *)
            outdir="./../results_CUCO/insert/SR"
            ;;
    esac

    mkdir -p "${outdir}"

    insert_path="${TRACE_DIR}/${file}"
    find_path="${TRACE_DIR}/${file}"

    echo "=============================================="
    echo "Trace file : ${file}"
    echo "Output dir : ${outdir}"
    echo "=============================================="

    for ops in "${operations[@]}"; do
        echo "  → Running num-keys=${ops}"
        base=2000000000
        oversub=$(( (ops - base) * 100 / base ))
        "${EXECUTABLE}" \
            --insert-path "${insert_path}" \
            --num-keys "${ops}" > "${outdir}/${oversub}.log" 2>&1
    done
done
