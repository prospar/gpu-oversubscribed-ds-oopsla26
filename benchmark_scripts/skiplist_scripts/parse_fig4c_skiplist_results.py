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

def extract_trace_type(filepath):
    """
    Extract trace type from the file path.

    MonotonicIncrease -> MI
    SparseUnique      -> SU
    DenseUnique       -> DU
    """
    path = filepath.lower()

    if "monotonicincrease" in path:
        return "MI"
    elif "sparseunique" in path:
        return "SU"
    elif "denseunique" in path:
        return "DU"
    else:
        return "Unknown"

def extract_input_size(filepath):
    """
    Try to extract input size from filename or nearby lines.
    Modify the regex to match your log format.
    """

    filename = os.path.basename(filepath)

    parts = Path(filepath).parts

    for i, part in enumerate(parts):
        if part in ("SparseUnique", "MonotonicIncrease", "DenseUnique"):
            if i > 0 and parts[i - 1].isdigit():
                return parts[i - 1]

    return "Unknown"


def extract_output_number(filepath):
    """
    output-128.log -> 128
    """
    filename = os.path.basename(filepath)
    m = re.search(r"output-blk(\d+)", filename)
    if m:
        return m.group(1)
    return "Unknown"

def parse_file(filepath, results):

    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
        
        trace_type = extract_trace_type(filepath)
        input_size = extract_input_size(filepath)
        filepath_str:list = os.path.normpath(filepath).split(os.sep)
        
        record = {
            "Impl" : filepath_str[2],
            "Input Size": input_size,
            "Trace Type": trace_type,
            "Insert Time": "",
            "Search Time": ""
        }

        for i, line in enumerate(lines):
            operation:str=""
            if "Median Insert Time: " in line:
                m = re.search(r"Median Insert Time:\s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*ms", line)
                if m:
                    record["Insert Time"] = round(float(m.group(1))/1000,2) # converting to secs
            if "Median Search Time: " in line:
                m = re.search(r"Median Search Time:\s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*ms", line)
                if m:
                    record["Search Time"] = round(float(m.group(1))/1000,2) # converting to secs
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


def write_csv(results, outfile="fig4c_study_skiplist.csv"):

    fields = [
        "Impl",
        "Input Size",
        "Trace Type",
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
        print("Usage: python parse_motivation_skiplist_results.py <root_directory>")
        sys.exit(1)

    csv_name_str = "fig4c_study_skiplist.csv"

    print(f'{csv_name_str}')
    root = sys.argv[1]

    if not os.path.isdir(root):
        print("Invalid directory")
        sys.exit(1)

    results = walk_directory(root)
    write_csv(results, csv_name_str)