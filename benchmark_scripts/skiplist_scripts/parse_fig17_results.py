#!/usr/bin/env python3
"""
Recursively search nested directories for log files and extract blocks containing:

    Insert() kernel
    Search() kernel

along with the next three lines after each match.

Usage:
    python parse_logs.py <root_directory>

Example:
    python parse_logs.py ./results
"""
#!/usr/bin/env python3

import os
import re
import csv
import sys
from pathlib import Path


def is_log_file(filename):
    return filename.lower().endswith((".log", ".txt", ".out", ".err"))


def extract_impl(filepath):
    """
    Extract implementation name from

    .../applications_study/<implementation>/...
    """

    parts = Path(filepath).parts

    for i, part in enumerate(parts):
        if part == "applications_study":
            if i + 1 < len(parts):
                return parts[i + 1]

    return "Unknown"


def extract_output_number(filepath):
    """
    output_ovr10.log -> 10
    """
    filename = os.path.basename(filepath)
    m = re.search(r"output_ovr(\d+)", filename)
    if m:
        return m.group(1)
    return "Unknown"

def parse_file(filepath, results):

    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

        input_size = extract_output_number(filepath)
        impl_name = extract_impl(filepath)

        if "classifier" in impl_name:
            record = {
                "Impl" : impl_name,
                "Input Size": input_size,
                "Insert Time": "",
                "Search Time": ""
            }

            for i, line in enumerate(lines):
                operation:str=""
                if "Total build time (GPU): " in line:
                    m = re.search(r"Total build time \(GPU\): \s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*ms", line)
                    if m:
                        record["Insert Time"] = round(float(m.group(1))/1000,2) # converting to secs

                if "Total search time (GPU): " in line:
                    m = re.search(r"Total search time \(GPU\):\s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*ms", line)
                    if m:
                        record["Search Time"] = round(float(m.group(1))/1000,2) # converting to secs
            results[filepath] = record
        elif "kmer" in impl_name:
            record = {
                "Impl" : impl_name,
                "Input Size": input_size,
                "Insert Time": "",
                "Search Time": ""
            }

            for i, line in enumerate(lines):
                operation:str=""
                if "K-mer count time (GPU): " in line:
                    m = re.search(r"K-mer count time \(GPU\): \s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*ms", line)
                    if m:
                        record["Insert Time"] = round(float(m.group(1))/1000,2) # converting to secs

                # if "Total search time (GPU): " in line:
                #     m = re.search(r"Total search time \(GPU\):\s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*ms", line)
                #     if m:
                #         record["Search Time"] = round(float(m.group(1))/1000,2) # converting to secs
            record["Search Time"] = 0.0
            results[filepath] = record

    except Exception as e:
        print(f"Could not read {filepath}: {e}")


def walk_directory(root_dir):

    results = {}

    for dirpath, _, filenames in os.walk(root_dir):
        for fname in filenames:
            if is_log_file(fname):
                parse_file(os.path.join(dirpath, fname), results)

    return list(results.values())


def write_csv(results, outfile="fig_17_study.csv"):

    fields = [
        "Impl",
        "Input Size",
        "Insert Time",
        "Search Time"
    ]

    with open(f'figures_skiplist/{outfile}', "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(results)

    print(f"Wrote {len(results)} records to {outfile}")


if __name__ == "__main__":

    if len(sys.argv) != 2:
        print("Usage: python parse_fig16_results.py <root_directory>")
        sys.exit(1)

    csv_name_str = "fig17_study.csv"

    print(f'{csv_name_str}')
    root = sys.argv[1]

    if not os.path.isdir(root):
        print("Invalid directory")
        sys.exit(1)

    results = walk_directory(root)
    write_csv(results, csv_name_str)