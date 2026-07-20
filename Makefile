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
APP_Path=./gpu/applications

SL_Path=./gpu/skiplist
TRACE_DIR=./tracegen_scripts

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
	${NVCC} ${CUDAFLAGS} --expt-extended-lambda ${CUDAINC} $< -o $(BIN)/$@.out 
	
cuco-search: ${CUCO_Path}/find_test.cu
	${NVCC} ${CUDAFLAGS} --expt-extended-lambda ${CUDAINC} $< -o $(BIN)/$@.out 
	
#Applications Commands
metacache-htuvm: ${APP_Path}/metacache.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out

metacache-htovs: ${APP_Path}/metacache_HoH.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out

kmer-htuvm: ${APP_Path}/kmer_counting.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out
	
kmer-htovs: ${APP_Path}/kmer_counting_HoH.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out

# trace-gen for skiplist
trace-gen-25e7: ${TRACE_DIR}/tracegen_skiplist.cpp
	${CXX} -O3 -std=c++17 ${TRACE_DIR}/tracegen_skiplist.cpp -o ${BIN}/trace-gen-25e7.out -DPRINT_TRACE -DTRACE_STEP=250000000

# for testing of trace-generation
trace-gen-1e7: ${TRACE_DIR}/tracegen_skiplist.cpp
	${CXX} -O3 -std=c++17 ${TRACE_DIR}/tracegen_skiplist.cpp -o ${BIN}/trace-gen-1e7.out -DPRINT_TRACE -DTRACE_STEP=100000000

# target for sl-uvm
sl-uvm-baseline: ${SL_Path}/trace_bm_gfsl_uvm.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DBATCH_IMPL -DUVM_PREFETCH_HINT

sl-uvm-kpw: ${SL_Path}/trace_bm_gfsl_uvm.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DBATCH_IMPL -DUVM_PREFETCH_HINT -DBUSY_WAIT

sl-uvm: ${SL_Path}/trace_bm_gfsl_uvm.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DBATCH_IMPL -DUVM_PREFETCH_HINT -DOPT_GRID -DBUSY_WAIT


sl-uvm-sort: ${SL_Path}/trace_bm_gfsl_uvm.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DENABLE_SORT -DBATCH_IMPL -DUVM_PREFETCH_HINT -DENABLE_SORT_INSERT -DOPT_GRID -DBUSY_WAIT

# target for sl-ovs
sl-ovs-baseline: ${SL_Path}/trace_bm_gfsl_hetero.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DBATCH_IMPL -DUVM_PREFETCH_HINT

sl-ovs: ${SL_Path}/trace_bm_gfsl_hetero.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DBATCH_IMPL -DUVM_PREFETCH_HINT -DBUSY_WAIT -DOPT_GRID

sl-ovs-sort: ${SL_Path}/trace_bm_gfsl_hetero.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DBATCH_IMPL -DENABLE_SORT -DUVM_PREFETCH_HINT -DENABLE_SORT_INSERT -DBUSY_WAIT -DOPT_GRID

#applications
sluvm_classifier: ${SL_Path}/trace_bm_gfsl_classifier.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out 

slovs_classifier: ${SL_Path}/trace_bm_gfsl_hetero_classifier.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out

sluvm_kmer: ${SL_Path}/trace_bm_gfsl_kmer.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out

slovs_kmer: ${SL_Path}/trace_bm_gfsl_hetero_kmer.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out


#additional targets for different variant of sl-uvm described in section 4.2.1 of the paper

skiplist-fixedindex-batch-sort: ${SL_Path}/trace_bm_gfsl_uvm.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DFIXED_INDEX -DBATCH_IMPL -DENABLE_SORT -DUVM_PREFETCH_HINT -DENABLE_SORT_INSERT
# separate pool optimization 
skiplist-separatepool-busywait-sort: ${SL_Path}/trace_bm_gfsl_uvm.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DSEPARATE_POOL -DBATCH_IMPL -DUVM_PREFETCH_HINT -DBUSY_WAIT -DBUSY_WAIT_SEARCH -DENABLE_SORT -DENABLE_SORT_INSERT
# unsorted optimization
skiplist-unsorted-busywait-sort: ${SL_Path}/trace_bm_gfsl_uvm.cu
	${NVCC} ${CUDAFLAGS} -I${INC} $< -o $(BIN)/$@.out -DUNSORTED_IMPL -DBATCH_IMPL -DENABLE_SORT -DUVM_PREFETCH_HINT -DENABLE_SORT_INSERT -DBUSY_WAIT -DBUSY_WAIT_SEARCH

clean:
	cd ${HH_Path} && rm *.out && cd ../..
	cd ${UVM_HT_Path} && rm driver_*.out && cd ../..

