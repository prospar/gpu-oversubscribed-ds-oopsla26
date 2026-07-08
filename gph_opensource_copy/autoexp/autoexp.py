import json
import itertools
import subprocess
import csv
import os
import random
import time
import datetime

def parseConfig(config_data):
    parameterBlocks = []
    ruleBlocks = []
    dependentParaBlocks = []
    resultBlocks = []
    
    for block in config_data:
        if block["type"] == "parameter":
            parameterBlocks.append(block)
        if block["type"] == "dependentParameter":
            dependentParaBlocks.append(block)
        if block["type"] == "rule": 
            ruleBlocks.append(block)
        if block["type"] == "meta":
            metaBlock = block
        if block['type'] == "resultMetric":
            resultBlocks.append(block)
    return parameterBlocks, dependentParaBlocks, ruleBlocks, metaBlock, resultBlocks

def autoexp(config_json_location, need_check_before_start=True):
    print("Load configurtion file {}".format(config_json_location))
    with open(config_json_location, "r+") as f:
        config_data = json.load(f)
    parameterBlocks, dependentParaBlocks, ruleBlocks, metaBlock, resultBlocks = parseConfig(config_data)

    parameters = [(param['paraName'], param['replaceTo'], param['cotainKeyWord'], param['dir']) for param in parameterBlocks]
    combinations = list(itertools.product(*[p[1] for p in parameters]))
    named_combinations = []
    for combo in combinations:
        named_combo = {parameters[i][0]: value for i, value in enumerate(combo)}
        named_combinations.append(named_combo)

    total_combo_len = len(named_combinations)

    samplePercentage = metaBlock['samplePercentage']

    named_combinations = random.sample(named_combinations, k=int(len(named_combinations)*samplePercentage))

    print("Total parameter combinations are {}, after sampling {} combination will be run.".format(total_combo_len, len(named_combinations)))
    if need_check_before_start:
        goornot = input("Enter yes to continue...")

        if ("y" not in goornot.lower()):
            exit(-1)

    print("Autoexp started...")
    st = time.time()

    experiments_result_set = []
    for i, combo in enumerate(named_combinations):
        
        if i > 0:
            elps = time.time() - st
            remainingTime = elps * 1.0 / i * (len(named_combinations) - i)
            print("[{}]===================={}% ({} spent, {} left estimated)===================".format(datetime.datetime.now(),i * 100.0 / len(named_combinations), time.strftime("%H:%M:%S", time.gmtime(elps)), time.strftime("%H:%M:%S", time.gmtime(remainingTime))))

        values = {}
        for key, value in combo.items():
            values[key] = value["paraValue"]
        for key, value in values.items():  
            print("{}\t\t\t{}".format(key, value))
        for param in parameters:
            paraName, replaceTo, cotainKeyWord, directory = param
            with open(directory, 'r', encoding='utf-8') as file:
                lines = file.readlines()
            with open(directory, 'w', encoding='utf-8') as file:
                cnt = 0
                for line in lines:
                    if cotainKeyWord in line:
                        line = combo[paraName]['line'] + '\n'
                        cnt += 1
                        if (cnt > 1):
                            print("======= Warning: parameter {} has more than one target lines.".format(paraName))
                        if (cotainKeyWord not in line):
                            print("======= Warning: parameter {} may have inconsistent cotainKeyWord and replaceTo.".format(paraName))
                    file.write(line)
        valid = True
        for rule in ruleBlocks:


            exec(rule['pythonCodeAssertTrue'])
            print(rule['pythonCodeAssertTrue'])
            execRes = locals()['res']
            if (execRes == False):
                valid = False
                print("Violate rule: {}".format(rule['pythonCodeAssertTrue']))
                break
        for dependentPara in dependentParaBlocks:
            directory = dependentPara['dir']
            with open(directory, 'r', encoding='utf-8') as file:
                lines = file.readlines()
            with open(directory, 'w', encoding='utf-8') as file:
                for line in lines:
                    if dependentPara['cotainKeyWord'] in line:
                        exec(dependentPara['pythonCodeReplaceTo'])
                        execRes = locals()['res']
                        line = execRes + '\n'
                    file.write(line)

        # s = input("input any integer enter to continue")
        if (not valid): continue

        runResultFileName = "{}.csv".format("|".join(["{}={}".format(t[0], t[1]) for t in values.items()]))
        runResultFilePath = os.path.join(metaBlock['outputDir'],'runResultArchieve',runResultFileName)
        if os.path.exists(runResultFilePath):
            print("Experiments result already exists, skipped")
            continue

        compileResult = subprocess.run(metaBlock['compileCommand'].split(), stdout=subprocess.PIPE).stdout
        print("Mission {} Compile complete.".format(i))
        runResult = subprocess.run(metaBlock['runCommand'].split(), stdout=subprocess.PIPE).stdout

        print("[{}] Mission {} Run complete.".format(datetime.datetime.now(), i))

        outputDir = os.path.join(metaBlock['outputDir'])
        outputArchieveDir = os.path.join(metaBlock['outputDir'],'runResultArchieve')
        if not os.path.exists(outputDir): os.makedirs(outputDir)
        if not os.path.exists(outputArchieveDir): os.makedirs(outputArchieveDir)

        with open(os.path.join(metaBlock['outputDir'],'runResultArchieve',runResultFileName), 'w', newline='') as f:
            f.write(runResult.decode('utf-8'))

        for result in resultBlocks:
            runResultLines = runResult.decode('utf-8').split('\n')
            for line in runResultLines:
                if result['containKeyWord'] in line:
                    try:
                        exec(result['pythonCodeFormatter'])
                        execRes = locals()['res']
                        values[result['metricName']] = execRes
                        values['error'] = ""
                    except Exception as e:
                        values['error'] = "{}".format(str(e).replace('\n',' '))



        # Extension: ncu analyze
        if metaBlock['ext_ncu_on']:
            exec(metaBlock['ext_ncu_run_condition'])
            execRes = locals()['res']
            if execRes:
                ncurepResultFileName = runResultFileName.replace(".csv",".ncu-rep")
                ncurepResultFilePath = os.path.join(metaBlock['outputDir'],'runResultArchieve',ncurepResultFileName)
                ncuruncmd = ["sh"]
                ncuruncmd.extend(["./ncu_perf.sh"])
                ncuruncmd.extend(metaBlock['runCommand'].split())
                ncuruncmd.extend([ncurepResultFilePath])
                print("Running ncuexp {}".format(ncuruncmd))
                subprocess.run(ncuruncmd)
            else:
                print("ext_ncu_on is true but the run condition does not match.")




        # write result to csv
        experiments_result_set.append(values)

        for key, value in values.items():  
            print("{}\t\t\t{}".format(key, value))

        max_len = 0
        for i, e in enumerate(experiments_result_set):
            if len(experiments_result_set[i].keys()) > max_len:
                max_len = len(experiments_result_set[i].keys())
                headers = experiments_result_set[i].keys()
                
        # Write data to CSV file
        with open(os.path.join(metaBlock['outputDir'], 'experiments_results.csv'), 'w', newline='') as f:
            writer = csv.DictWriter(f, headers)
            writer.writeheader()
            writer.writerows(experiments_result_set)
    