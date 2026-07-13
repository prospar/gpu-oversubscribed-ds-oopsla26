#!/bin/bash

set -e

cd ../../bin


reserve=(
    2.91
    4.92
    6.4
)

for res in "${reserve[@]}"; do
    if [ "$res" = 2.91 ]; then
        outdir="../results_applications/htuvm/10"
    elif [ "$res" = 4.92 ]; then
        outdir="../results_applications/htuvm/30"
    else
        outdir="../results_applications/htuvm/50"
    fi
    mkdir -p "$outdir"

    ./metacache-htuvm.out "$res" > "$outdir/metacache.log"
    ./kmer-htuvm.out "$res" > "$outdir/kmer.log"
done