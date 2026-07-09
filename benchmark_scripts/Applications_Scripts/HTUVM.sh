#!/bin/bash

set -e

cd ../../bin


reserve=(
    2.91
    4.92
    6.4
)

for res in "${reserve[@]}"; do
    outdir="../results_applications/htuvm/${res}"
    mkdir -p "$outdir"

    ./metacache-htuvm.out "$res" > "$outdir/metacache.log"
    ./kmer-htuvm.out "$res" > "$outdir/kmer.log"
done