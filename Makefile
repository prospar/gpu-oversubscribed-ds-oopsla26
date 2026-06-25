NVCC=nvcc
CUDAFLAGS=-std=c++17 -arch=sm_75 -lineinfo --source-in-ptx -O3  


LIB=./libraries
INC=./include

BIN=./bin
$(shell mkdir -p $(BIN))

HT_OVS_Path=./hetero/hashtable
HT_UVM_Path=./gpu/hashtable


STATS_DEBUG=-DKEY_CHECK

UVM_MA_ALL= -DUVM_MEM_ADVISE_SR -DUVM_MEM_ADVISE_SA -DUVM_MEM_ADVISE_SP 
UVM_ALL= -DUVM_MEM_ADVISE_SR -DUVM_MEM_ADVISE_SA -DUVM_MEM_ADVISE_SP -DUVM_PREFETCH_HINT


SL_Path=./gpu/skiplist

#HT-UVM commands
	
uvm-baseline: ${HT_UVM_Path}/driver_hashtable_UVM.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DCG	
	
uvm-opt-4: ${HT_UVM_Path}/driver_hashtable_UVM.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG -DCOOP_GROUP_SIZE=4
	
uvm-opt-8: ${HT_UVM_Path}/driver_hashtable_UVM.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG -DCOOP_GROUP_SIZE=8	
	
uvm-opt: ${HT_UVM_Path}/driver_hashtable_UVM.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG
	
uvm-opt-32: ${HT_UVM_Path}/driver_hashtable_UVM.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG -DCOOP_GROUP_SIZE=32
	
uvm-opt-sort: ${HT_UVM_Path}/driver_hashtable_UVM.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG -DBSORT

# HT-OVS commands

htovs-opt-4: ${HT_OVS_Path}/driver_hetero_hash_batch.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out ${HETERO_PTHREAD_FLAG} -DOUTER_HASHTABLE_MEM_ADVISE_SA -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG -DBSORT -DCOOP_GROUP_SIZE=4
	
htovs-opt-8: ${HT_OVS_Path}/driver_hetero_hash_batch.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out ${HETERO_PTHREAD_FLAG} -DOUTER_HASHTABLE_MEM_ADVISE_SA -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG -DBSORT -DCOOP_GROUP_SIZE=8

htovs-opt: ${HT_OVS_Path}/driver_hetero_hash_batch.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out ${HETERO_PTHREAD_FLAG} -DOUTER_HASHTABLE_MEM_ADVISE_SA -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG -DBSORT
	
htovs-opt-32: ${HT_OVS_Path}/driver_hetero_hash_batch.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out ${HETERO_PTHREAD_FLAG} -DOUTER_HASHTABLE_MEM_ADVISE_SA -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG -DBSORT -DCOOP_GROUP_SIZE=32
	
#Trace gen commands


clean:
	cd ${HH_Path} && rm *.out && cd ../..
	cd ${UVM_HT_Path} && rm driver_*.out && cd ../..

