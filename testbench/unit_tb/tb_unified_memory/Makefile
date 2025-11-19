# Makefile for the firmware

# BASE_DIR=../..
# TOP_MODULE=tb_unified_memory
# SIM_NAME=tb_main

# all: build sim

# build:
# 	verilator --cc --exe --build --no-timing\
# 		--top-module ${TOP_MODULE} \
# 		-CFLAGS "-Iobj_dir" \
# 		${BASE_DIR}/includes/pkg_riscv_instructions.sv \
# 		${BASE_DIR}/includes/pkg_global_defs.sv \
# 		${TOP_MODULE}.sv \
# 		-I${BASE_DIR}/includes -I${BASE_DIR}/rtl -I${BASE_DIR}/rtl/datapath -Iobj_dir \
# 		${SIM_NAME}.cpp

# sim: build
# 	./obj_dir/V${TOP_MODULE}

# clean:
# 	rm -rf obj_dir

include ../includes/tb_common.mk

BASE_DIR = ../../..
TOP_MODULE = tb_unified_memory
RTL_SOURCES = ${RTL_DIR}/mem_request_if.sv ${RTL_DIR}/unified_memory.sv