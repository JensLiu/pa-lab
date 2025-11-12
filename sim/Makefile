# Makefile for the firmware

BASE_DIR=..

all: build sim

build:
	verilator --cc --exe --build \
		--top-module datapath_pipelined \
		-CFLAGS "-Iobj_dir" \
		${BASE_DIR}/includes/pkg_riscv_instructions.sv \
		${BASE_DIR}/includes/pkg_global_defs.sv \
		${BASE_DIR}/rtl/datapath/datapath_pipelined.sv \
		-I${BASE_DIR}/includes -I${BASE_DIR}/rtl -I${BASE_DIR}/rtl/datapath -Iobj_dir \
		sim_main.cpp

firmware_obj:
	$(MAKE) -C ${BASE_DIR}/firmware && cp ${BASE_DIR}/firmware/firmware.mem inst_mem.hex

sim: build firmware_obj
	./obj_dir/Vdatapath_pipelined

clean:
	rm -rf obj_dir