import json
import pandas as pd

res_file = "lookup_dataset_pos_lf.txt"

exp_res = []

with open(res_file, "r+") as f:
    insert_time = 0
    search_time = 0
    while True:
        line = f.readline()
        if line:
            if "default_exp" in line:
                new_exp = json.loads(line.strip())
                new_exp["insert_time"] = insert_time
                new_exp["search_time"] = search_time
                exp_res.append(new_exp)
            if "TIMING" in line:
                if "insert" in line:
                    insert_time = float(line.split("IMING:")[1].split("ms")[0].strip())
                if "search" in line:    
                    search_time = float(line.split("IMING:")[1].split("ms")[0].strip())
        else:
            break

print(exp_res)

df = pd.DataFrame(columns=['competitor', 'correct_rate', 'dataset', 'lf', 'workload', 'trial', 'workloadlen','insert_time','search_time'])  # Define the columns of your table

data = []
for exp_json in exp_res:
    competitor = exp_json['exp_batch_res'][0]['competitor']
    correct_rate = int(exp_json['exp_batch_res'][0]['correct_checked']) / int(exp_json['exp_batch_res'][0]['total_checked'])
    dataset = exp_json['exp_batch_res'][0]['dataset'] 
    lf = str(exp_json['exp_batch_res'][0]['load_factor_upper_bound']) 
    workload = exp_json['exp_batch_res'][0]['workload']
    trial = int(exp_json['exp_batch_res'][0]['comment'].replace("trial: ","")) 
    workloadlen = int(exp_json['exp_batch_res'][0]['workload_len']) 
    insert_throughput = int(exp_json['exp_batch_res'][0]['dataset_len']) / float(exp_json['insert_time']) / 1000
    search_throughput = workloadlen / float(exp_json['search_time']) / 1000
    data.append([competitor, correct_rate, dataset, lf, workload, trial, workloadlen, insert_throughput, search_throughput])

df = pd.DataFrame(data, columns=['competitor', 'correct_rate', 'dataset', 'lf', 'workload', 'trial', 'workloadlen','insert_throughput','search_throughput'])

print(df)
df.to_csv('df.csv', index=False)
aggregated_df = df.groupby(['competitor', 'dataset', 'lf', 'workload', 'workloadlen']).agg({'insert_throughput': 'mean', 'search_throughput': 'mean', 'correct_rate': 'mean'}).reset_index()

print(aggregated_df)
aggregated_df.to_csv('aggregated_df.csv', index=False, float_format=f'%.3f')