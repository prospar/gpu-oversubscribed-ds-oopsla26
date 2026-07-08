import subprocess

result = subprocess.run('cmake -B build'.split(), stdout=subprocess.PIPE)
result = subprocess.run(['cmake',"--build","build"], stdout=subprocess.PIPE)
result = subprocess.run(['./build/GPHOS/pre_exp'], stdout=subprocess.PIPE)
print("============python captured ========: {}".format(result.stdout.decode("utf-8").split("\n")))

lines = result.stdout.decode("utf-8").split("\n")
for line in lines:
    if "lookup throughput: " in line:
        res = int(line.strip().split(' ')[2])
        print("============python captured ========: lookup throughput is {}".format(res))

print("You cannot print this before last end")