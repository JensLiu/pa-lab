# Makefile for the firmware

BASE_DIR=..

VERILATOR_UNIQUE_FLAGS = -x-assign unique -x-initial unique
VERILATOR_BUILD_FLAGS = --cc -exe --main --timing --build --exe -j 0
VERILATOR_TRACE_FLAGS = --trace-fst --trace-params --trace-structs --trace-underscore
VERILATOR_FLAGS = --sv -CFLAGS -fcoroutines "-Iobj_dir"  $(VERILATOR_UNIQUE_FLAGS) $(VERILATOR_TRACE_FLAGS) $(VERILATOR_BUILD_FLAGS) --timing
# VERILATOR_GRAPH_FLAGS = --dumpi-graph 1
VERILATOR_GRAPH_FLAGS =
CPP_SOURCES = sim_main.cpp

all: build sim

build:
		verilator -sv $(VERILATOR_TRACE_FLAGS) $(VERILATOR_GRAPH_FLAGS) --cc --exe --build -j 0 \
		--top-module datapath_pipelined \
		-CFLAGS "-Iobj_dir" \
		-I${BASE_DIR}/includes -I${BASE_DIR}/rtl -I${BASE_DIR}/rtl/datapath \
		-I${BASE_DIR}/cache -I${BASE_DIR}/memory -I${BASE_DIR}/reorder_buffer \
		-I${BASE_DIR}/store_buffer -Iobj_dir \
		${BASE_DIR}/includes/pkg_riscv_instructions.sv \
		${BASE_DIR}/includes/pkg_virtual_memory.sv \
		${BASE_DIR}/includes/pkg_global_defs.sv \
		${BASE_DIR}/rtl/*.sv \
		${BASE_DIR}/rtl/datapath/*.sv \
		${BASE_DIR}/rtl/cache/*.sv \
		${BASE_DIR}/rtl/memory/*.sv \
		${BASE_DIR}/rtl/reorder_buffer/*.sv \
		${BASE_DIR}/rtl/store_buffer/*.sv \
		${BASE_DIR}/rtl/virtual_memory/inner/*.sv \
		$(CPP_SOURCES)

firmware_obj:
	$(MAKE) -C ${BASE_DIR}/firmware && cp ${BASE_DIR}/firmware/firmware.mem memory.hex

sim: build firmware_obj
	./obj_dir/Vdatapath_pipelined

dfg:
	dot -Tpdf obj_dir/Vdatapath_pipelined_067_stl_orderg_acyc.dot -o dfg.pdf

clean:
	rm -rf obj_dir
	rm -f *.hex
	rm -f *.fst
	rm -f *.log