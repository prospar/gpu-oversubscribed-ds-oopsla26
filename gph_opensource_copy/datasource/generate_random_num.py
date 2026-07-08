import random

# Generate a list of unique random uint32 integers
random_integers = random.sample(range(0, 2**32-1), 100000000)

# Write the integers to a file
with open('random_key_encoded.txt', 'w') as file:
    for integer in random_integers:
        file.write(f"{integer}\n")

# Generate a list of unique random uint32 integers
random_integers = random.sample(range(1, 2**32-1), 100000000)

# Write the integers to a file
with open('random_value_encoded.txt', 'w') as file:
    for integer in random_integers:
        file.write(f"{integer}\n")