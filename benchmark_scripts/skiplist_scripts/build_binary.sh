#!/bin/bash
# folder to build skiplist binaries
mkdir -p bin

# binary for fig 4c and table9
make sl-uvm-baseline

# binary for table8
make sl-uvm-kpw

# binary for table10
make sl-ovs-baseline

# binaries for fig 16
make sl-uvm-sort
make sl-ovs-sort

#binaries for RHS of fig 17 and fig 
make sluvm_classifier
make slovs_classifier
make sluvm_kmer
make slovs_kmer
