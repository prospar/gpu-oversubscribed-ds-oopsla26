#!/bin/bash

set -e

cd ../../bin


reserve=(
    2.91
    4.92
    6.4
)

for res in "${reserve[@]}"; do
    outdir="../results_applications/htovs/${res}"
    mkdir -p "$outdir"

    ./metacache-htovs.out "$res" > "$outdir/metacache.log"
    ./kmer-htovs.out "$res" > "$outdir/kmer.log"
done