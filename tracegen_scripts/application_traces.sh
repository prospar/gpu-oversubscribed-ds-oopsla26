#!/bin/bash
# the dataset for build
wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/635/GCF_000001635.27_GRCm39/GCF_000001635.27_GRCm39_genomic.fna.gz
gunzip -c GCF_000001635.27_GRCm39_genomic.fna.gz > skiplist_traces/GCF_000001635.27_GRCm39_genomic.fna

# the dataset for classification
wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/002/285/GCF_000002285.3_CanFam3.1/GCF_000002285.3_CanFam3.1_genomic.fna.gz
gunzip -c GCF_000002285.3_CanFam3.1_genomic.fna.gz > skiplist_traces/GCF_000002285.3_CanFam3.1_genomic.fna