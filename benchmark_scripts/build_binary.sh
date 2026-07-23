#!/bin/bash
cd ../


# For skip list

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


#For hash table

#binaries for fig 9 fig 10 fig 12 fig 15
make uvm-opt
make uvm-opt-sort
make htovs-opt
make cuco-insert
make cuco-search

#binaries for fig 11 lhs
make uvm-opt-4
make uvm-opt-8
make uvm-opt-32

make htovs-opt-4
make htovs-opt-8
make htovs-opt-32

#binaries for fig 4a and fig 4b
make uvm-baseline

#binaries for fig 17 lhs
make metacache-htuvm
make metacache-htovs
make kmer-htuvm
make kmer-htovs