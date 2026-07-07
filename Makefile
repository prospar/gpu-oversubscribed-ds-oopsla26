NVCC=nvcc
CUDAFLAGS=-std=c++17 -arch=sm_75 -lineinfo --source-in-ptx -O3  


LIB=./libraries
INC=./include
CUDAINC=-I./cuCollections/tests \
        -I./cuCollections/include \
        -I./cccl/thrust \
        -I./cccl/libcudacxx/include \
        -I./cccl/cub \
        -I./catch2/src/ \
        -I./catch2/build_cmake/generated-includes \
        -L./catch2/build_cmake/src \
         -lCatch2 \
         -lCatch2Main


BIN=./bin
$(shell mkdir -p $(BIN))

HT_OVS_Path=./gpu/hashtable
HT_UVM_Path=./gpu/hashtable
CUCO_Path= ./cuCollections/tests/static_map

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
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out ${HETERO_PTHREAD_FLAG} -DOUTER_HASHTABLE_PREFETCH_HINT -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG -DBSORT -DCOOP_GROUP_SIZE=4
	
htovs-opt-8: ${HT_OVS_Path}/driver_hetero_hash_batch.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out ${HETERO_PTHREAD_FLAG} -DOUTER_HASHTABLE_PREFETCH_HINT -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG -DBSORT -DCOOP_GROUP_SIZE=8

htovs-opt: ${HT_OVS_Path}/driver_hetero_hash_batch.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out ${HETERO_PTHREAD_FLAG} -DOUTER_HASHTABLE_PREFETCH_HINT -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG -DBSORT
	
htovs-opt-32: ${HT_OVS_Path}/driver_hetero_hash_batch.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out ${HETERO_PTHREAD_FLAG} -DOUTER_HASHTABLE_PREFETCH_HINT -DUVM_MEM_ADVISE_SA -DUVM_PREFETCH_HINT -DCG -DBSORT -DCOOP_GROUP_SIZE=32

#Trace gen commands


#cuCollections Commands:
cuco-insert: ${CUCO_Path}/insert_or_assign_test.cu
	${NVCC} ${CUDAFLAGS} --expt-extended-lambda ${CUDAINC} $< -o ${BIN}/$@.out 
	
cuco-search: ${CUCO_Path}/find_test.cu
	${NVCC} ${CUDAFLAGS} --expt-extended-lambda ${CUDAINC} $< -o ${BIN}/$@.out 
	
clean:
	cd ${HH_Path} && rm *.out && cd ../..
	cd ${UVM_HT_Path} && rm driver_*.out && cd ../..

