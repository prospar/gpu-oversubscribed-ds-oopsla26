#! /bin/bash

set -e

operations=(
            2000000000 
            2500000000 
            3000000000 
            3500000000 
            4000000000
           )


cd ./../../bin/



outdir="./../results_CG/htuvm/CG_4"
mkdir -p "$outdir"

for ops in "${operations[@]}"
do
    base=2000000000
    oversub=$(( (ops - base) * 100 / base ))
    ./uvm-opt-4.out -ops="$ops" -add="$ops" -fil=1 -rem=0 -rns=1 -tra="$file" -gbs=100000000 -rng=1048576 > "${outdir}/${oversub}.log"
done



outdir="./../results_CG/htuvm/CG_8"
mkdir -p "$outdir"
for ops in "${operations[@]}"
do
    base=2000000000
    oversub=$(( (ops - base) * 100 / base ))
    ./uvm-opt-8.out -ops="$ops" -add="$ops" -fil=1 -rem=0 -rns=1 -tra="$file" -gbs=100000000 -rng=1048576 > "${outdir}/${oversub}.log"
done



outdir="./../results_CG/htuvm/CG_16"
mkdir -p "$outdir"
for ops in "${operations[@]}"
do
    base=2000000000
    oversub=$(( (ops - base) * 100 / base ))
    ./uvm-opt.out -ops="$ops" -add="$ops" -fil=1 -rem=0 -rns=1 -tra="$file" -gbs=100000000 -rng=1048576 > "${outdir}/${oversub}.log"
done



outdir="./../results_CG/htuvm/CG_32"
mkdir -p "$outdir"
for ops in "${operations[@]}"
do
    base=2000000000
    oversub=$(( (ops - base) * 100 / base ))
    ./uvm-opt-32.out -ops="$ops" -add="$ops" -fil=1 -rem=0 -rns=1 -tra="$file" -gbs=100000000 -rng=1048576 > "${outdir}/${oversub}.log"
done
