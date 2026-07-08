import hashlib
from collections import defaultdict
import random
from collections import Counter

def check_skewness(file_path):
    total_count = 0
    distinct_numbers = set()
    number_counts = {}

    try:
        with open(file_path, 'r') as file:
            for line in file:
                line = line.strip()
                if line:
                    try:
                        number = int(line)
                        total_count += 1
                        distinct_numbers.add(number)
                        if number in number_counts:
                            number_counts[number] += 1
                        else:
                            number_counts[number] = 1
                    except ValueError:
                        print(f"Warning: '{line}' is not a valid integer. Skipping...")

        distinct_count = len(distinct_numbers)
        
        # Sort numbers by frequency to get the most common
        sorted_counts = sorted(number_counts.values(), reverse=True)

        # Calculate cumulative counts
        cumulative_counts = []
        cumulative_sum = 0
        
        for count in sorted_counts:
            cumulative_sum += count
            cumulative_counts.append(cumulative_sum)

        # Print total and distinct counts
        print(f"Total number of integers: {total_count}")
        print(f"Total number of distinct integers: {distinct_count}\n")

        percentages = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50,
                       55, 60, 65, 70, 75, 80, 85, 90, 95, 100]

        print(f"{'Percent (%)':<12} {'Count':<10} {'Cumulative Count':<15} {'Cumulative Percentage'}")
        for percent in percentages:
            index = (percent * len(cumulative_counts)) // 100 - 1
            if index >= 0:
                count = cumulative_counts[index]
                cum_percentage = (count / total_count) * 100 if total_count > 0 else 0
                print(f"{percent:<12} {cumulative_counts[index]:<10} {count:<15} {cum_percentage:.2f}%")
            else:
                print(f"{percent:<12} {0:<10} {0:<15} {0:.2f}%")

    except FileNotFoundError:
        print(f"Error: The file '{file_path}' was not found.")
    except Exception as e:
        print(f"An error occurred: {e}")

check_skewness("tao_workload_pos100_size200000000.txt")