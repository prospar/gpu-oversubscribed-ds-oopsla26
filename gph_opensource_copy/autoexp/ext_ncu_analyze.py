import os
import subprocess as subp
from collections import defaultdict

def convert_unit(value, unit):
    value = value.replace(",","")
    value = float(value)

    # cycles per second conversion
    if unit == "cycle/nsecond":
        value = value * 1000000000.0
        unit = "cycle/second"
    elif unit == "cycle/usecond":
        value = value * 1000000.0
        unit = "cycle/second"
    elif unit == "cycle/msecond":
        value = value * 1000.0
        unit = "cycle/second"
    elif unit == "cycle/second":
        value = value
        unit = "cycle/second"

    # bytes per second conversion
    elif unit == "byte/second":
        value = value
        unit = "byte/second"
    elif unit == "Kbyte/second":
        value = value * 1024.0
        unit = "byte/second"
    elif unit == "Mbyte/second":
        value = value * (1024.0**2)
        unit = "byte/second"
    elif unit == "Gbyte/second":
        value = value * (1024.0**3)
        unit = "byte/second"
    elif unit == "Tbyte/second":
        value = value * (1024.0**4)
        unit = "byte/second"

    # bytes conversion
    elif unit == "byte":
        value = value
        unit = "byte"
    elif unit == "Kbyte":
        value = value * 1024.0
        unit = "byte"
    elif unit == "Mbyte":
        value = value * (1024.0**2)
        unit = "byte"
    elif unit == "Gbyte":
        value = value * (1024.0**3)
        unit = "byte"
    elif unit == "Tbyte":
        value = value * (1024.0**4)
        unit = "byte"

    # seconds conversion
    elif unit == "usecond":
        value = value / 1000000.0
        unit = "second"
    elif unit == "msecond":
        value = value / 1000.0
        unit = "second"
    elif unit == "second":
        value = value / 1000.0
        unit = "second"

    # units no need for conversion
    elif unit == "%":
        value = value
    elif unit == "block":
        value = value
    elif unit == "cycle":
        value = value
    elif unit == "request":
        value = value
    elif unit == "sector":
        value = value
    elif unit == "inst":
        value = value
    elif unit == "warp":
        value = value
    elif unit == "cycle":
        value = value
    elif unit == "register/thread":
        value = value
    elif unit == "thread":
        value = value
    elif unit == "inst/cycle":
        value = value
    elif unit == "":
        value = value

    # handle exception
    else:
        raise Exception(f"{unit} is not supported.")

    return (value, unit)

class NcuParser:
    def __init__(self, ncu_rep_path=".", target_metrics=["Block Size"], target_kernel_name_keyword=""):
        NCU_PATH="ncu"

        self.results = defaultdict(dict)
        p = subp.Popen(
            [
                NCU_PATH,
                "--import",
                ncu_rep_path,
                "--csv",
            ],
            stdin=subp.PIPE,
            stdout=subp.PIPE,
            stderr=subp.STDOUT,
        )
        out, _ = p.communicate()
        out = out.decode("utf-8")

        columns = {v:i for i, v in enumerate(["ID","Process ID","Process Name","Host Name","Kernel Name","Context","Stream","Block Size","Grid Size","Device","CC","Section Name","Metric Name","Metric Unit","Metric Value","Rule Name","Rule Type","Rule Description"])}
        for line in out.split("\n"):
            line = line.strip(",").strip('"').split('","')
            if len(line) <= columns["Metric Value"]:
                continue
            ID = line[columns["ID"]]
            kernel_name = line[columns["Kernel Name"]]
            metric_name = line[columns["Metric Name"]]
            metric_unit = line[columns["Metric Unit"]]
            metric_value = line[columns["Metric Value"]]
            if (target_kernel_name_keyword != "" and target_kernel_name_keyword not in kernel_name):
                continue
            if (metric_name in target_metrics):
                self.results[0]["ID"] = ID
                self.results[0]["kernel_name"] = kernel_name
                v, u = convert_unit(metric_value, metric_unit)
                self.results[0][metric_name + "({})".format(u)] = v


# p = NcuParser("./competitors_default.ncu-rep", target_metrics=["dram__bytes.sum","Theoretical Occupancy","Achieved Occupancy"], target_kernel_name_keyword="DynamicHash::cuckoo_search")
# print(p.results)
