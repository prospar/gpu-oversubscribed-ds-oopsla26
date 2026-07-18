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

KEYWORDS = ["Total insert time for all batches"]


def is_log_file(filename):
    return filename.lower().endswith((".log", ".txt", ".out", ".err"))

def extract_trace_type(filepath):
    """
    Extract trace type from the file path.

    MonotonicIncrease -> MI
    DenseUnique       -> DU
    """
    path = filepath.lower()

    if "monotonicincrease" in path:
        return "MI"
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
        if part in ("DenseUnique", "MonotonicIncrease"):
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
        thread_block_size = extract_output_number(filepath)
        record = {
            "Trace Type": trace_type,
            "Insert Time": "",
        }

        for i, line in enumerate(lines):
            operation:str=""
            if "Median Insert Time: " in line:
                m = re.search(r"Median Insert Time:\s*(\d+(?:\.\d+)?)\s*ms", line)
                if m:
                    record["Insert Time"] = round(float(m.group(1))/1000,2) # converting to secs
        
        if trace_type not in results:
            results[trace_type] = {
                "Trace Type": trace_type
            }

        results[trace_type][f'blk{thread_block_size}'] = record["Insert Time"]

    except Exception as e:
        print(f"Could not read {filepath}: {e}")


def walk_directory(root_dir):

    results = {}

    for dirpath, _, filenames in os.walk(root_dir):
        for fname in filenames:
            if is_log_file(fname):
                parse_file(os.path.join(dirpath, fname), results)

    return list(results.values())


def write_csv(results, outfile="parsed_results_table9.csv"):

    fields = [
        "Trace Type",
        'blk64',
        'blk256',
        'blk1024', 
        'blk4096', 
        'blk16384',
        'blk262144',
        'blk65536',
        'blk1048576',
        'blk4194304'
    ]

    with open(outfile, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(results)

    print(f"Wrote {len(results)} records to {outfile}")


if __name__ == "__main__":

    if len(sys.argv) < 2:
        print("Usage: python parse_thread_block_results.py <root_directory>")
        sys.exit(1)

    csv_name_str = "table9.csv"

    print(f'{csv_name_str}')
    root = sys.argv[1]

    if not os.path.isdir(root):
        print("Invalid directory")
        sys.exit(1)

    results = walk_directory(root)
    write_csv(results, csv_name_str)