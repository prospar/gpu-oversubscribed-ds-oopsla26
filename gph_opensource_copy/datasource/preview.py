file_name = "tmp.txt"

with open(file_name, "r+") as f:
    count = 10
    while True:
        count -= 1
        if count <= 0: break
        line = f.readline()
        if line:
            print(line,end="")
        else:
            break