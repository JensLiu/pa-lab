# Makefile for the firmware

BASE_DIR=..

VERILATOR_UNIQUE_FLAGS = -x-assign unique -x-initial unique
VERILATOR_BUILD_FLAGS = --cc -exe --main --timing --build --exe -j 0
VERILATOR_TRACE_FLAGS = --trace-fst --trace-params --trace-structs --trace-underscore
VERILATOR_FLAGS = --sv -CFLAGS -fcoroutines "-Iobj_dir"  $(VERILATOR_UNIQUE_FLAGS) $(VERILATOR_TRACE_FLAGS) $(VERILATOR_BUILD_FLAGS) --timing
CPP_SOURCES = sim_main.cpp

all: build sim

build:
		verilator -sv $(VERILATOR_TRACE_FLAGS) --cc --exe --build -j 0 \
		--top-module datapath_pipelined \
		-CFLAGS "-Iobj_dir" \
		-I${BASE_DIR}/includes -I${BASE_DIR}/rtl -I${BASE_DIR}/rtl/datapath -Iobj_dir \
		${BASE_DIR}/includes/pkg_riscv_instructions.sv \
		${BASE_DIR}/includes/pkg_global_defs.sv \
		${BASE_DIR}/rtl/*.sv \
		${BASE_DIR}/rtl/datapath/*.sv \
		$(CPP_SOURCES)

firmware_obj:
	$(MAKE) -C ${BASE_DIR}/firmware && cp ${BASE_DIR}/firmware/firmware.mem inst_mem.hex

sim: build firmware_obj
	./obj_dir/Vdatapath_pipelined

clean:
	rm -rf obj_dir