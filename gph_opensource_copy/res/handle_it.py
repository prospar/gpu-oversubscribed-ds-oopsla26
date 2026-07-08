import os
import sys 
sys.path.append('./autoexp/')
from ext_ncu_analyze import NcuParser
import pandas as pd


def find_line(file, containKeyWords, pythonCodeFormatter):
    with open(file, "r+", encoding="utf-8") as f:
        line = f.readline()
        while line:
            if containKeyWords in line:
                exec(pythonCodeFormatter)
                execRes = locals()['res']
                return execRes
            line = f.readline()
    return None


def combine_ncurep_csv(folder_paths, target_kernels):
    table = []
    assert(len(folder_paths) == len(target_kernels))
    for i in range(len(folder_paths)):
        folder_path = folder_paths[i]
        target_kernel = target_kernels[i]
        target_folder = os.path.join(folder_path,"runResultArchieve")
        paras_name = []
        normal_metrics = [
            "lookup_throughput",
            "correctness",
            "search_time_ms"
        ]
        ncu_metrics = [
            "dram__bytes.sum","dram__bytes.sum.per_second","Memory Throughput","L1/TEX Cache Throughput","L2 Cache Throughput","Memory Throughput","L1/TEX Hit Rate","L2 Hit Rate","Max Bandwidth","Active Warps Per Scheduler","Eligible Warps Per Scheduler","No Eligible","One or More Eligible","Warp Cycles Per Executed Instruction","Executed Instructions","Theoretical Occupancy","Achieved Occupancy","Grid Size","Registers Per Thread","Block Size","Avg. Active Threads Per Warp",
            "smsp__cycles_active.avg",
            "smsp__cycles_active.max",
            "smsp__cycles_active.min",
            "smsp__cycles_active.sum"
        ]
        ncu_metrics_with_unit = []
        for file in os.listdir(target_folder):
            if file.endswith(".ncu-rep"):
                ncurep_file = os.path.join(target_folder, file)
                csv_file = ncurep_file.replace(".ncu-rep",".csv")
                if os.path.exists(ncurep_file) and os.path.exists(csv_file):
                    data = []
                    names = []
                    paras = os.path.basename(csv_file).replace(".csv","").split("|")
                    for para in paras:
                        data.append(para.split("=")[1])
                        names.append(para.split("=")[0])
                    if len(paras_name) == 0:
                        paras_name = names

                    lth = find_line(csv_file, "lookup throughput: ", "res = int(line.strip().split(' ')[2])")
                    crt = find_line(csv_file, "Correctness: ", "res = float(line.strip().split(' ')[1])")
                    serach_time = find_line(csv_file, "search)", "res = float(line.strip().split(' ')[1])")
                    data.append(lth)
                    data.append(crt)
                    data.append(serach_time)

                    result = NcuParser(ncurep_file, target_metrics=ncu_metrics, target_kernel_name_keyword=target_kernel).results
        
                    units = []
                    for metric in ncu_metrics:
                        for k,v in result[0].items():
                            if metric in k:
                                data.append(v)
                                units.append(k)
                    if len( ncu_metrics_with_unit) == 0:
                        ncu_metrics_with_unit = units

                    
                    table.append(data)
        columns = []
        columns.extend(paras_name)
        columns.extend(normal_metrics)
        columns.extend(ncu_metrics_with_unit)
    df = pd.DataFrame(table, columns=columns)
    df.to_csv(os.path.join(folder_path, "{}.csv".format("combined_result")), index=False)

# paths = ["res/gph_comp", "res/gph_comp", "res/gph_comp"]
# kernels = ["cuckoo_search", "cuckooLookupKernel_Naive", "warpcore::kernels::retrieve"]
# combine_ncurep_csv(paths, kernels)

# combine_ncurep_csv(["res/gph_global_cell_gph"],[""])
combine_ncurep_csv(["res/gph_comp_v3","res/gph_comp_v3","res/gph_comp_v3","res/gph_comp_v3"], ["cuckoo_search", "cuckooLookupKernel_Naive", "warpcore::kernels::retrieve","GPHOSGPUTableLookupKeyReturnValue"])
# combine_ncurep_csv(["perf/param_tune_geph_new_for_model"],[""])