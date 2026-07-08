file_name = "random_key_encoded.txt"
upper = 2**32-1
with open(file_name, "r+") as f:
    line_id = 0
    duplicated = set()
    while True:
        line_id += 1
        line = f.readline()
        if line:
            cont = int(line.strip())
            if not (0 <= cont <= upper):
                print("line {}: ERROR IN RANGE {}".format(line_id, cont))
                break
            if cont in duplicated:
                print("line {}: ERROR DUPLICATE {}".format(line_id,cont))
                break
            duplicated.add(cont)
        else:
            break