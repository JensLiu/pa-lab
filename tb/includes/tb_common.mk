# Common Makefile variables for testbenches

BASE_DIR = ../..
RTL_DIR = $(BASE_DIR)/rtl
INCLUDES = $(BASE_DIR)/includes
VERILATOR_UNIQUE_FLAGS = -x-assign unique -x-initial unique
VERILATOR_TRACE_FLAGS = --trace-fst
VERILATOR_BUILD_FLAGS = --cc -exe --main --timing --build --exe -j 0

VERILATOR_FLAGS = -CFLAGS -fcoroutines $(VERILATOR_UNIQUE_FLAGS) $(VERILATOR_TRACE_FLAGS) $(VERILATOR_BUILD_FLAGS)
PACKAGES = ${INCLUDES}/pkg_global_defs.sv ${INCLUDES}/pkg_riscv_instructions.sv


# common in all testbench Makefiles
SOURCES = $(PACKAGES) ${RTL_SOURCES} ./$(TOP_MODULE).sv

.PHONY: all build run clean

all: build run

build:
	@verilator $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) $(SOURCES)

run: build
	@./obj_dir/V$(TOP_MODULE)

clean:
	@rm -rf obj_dir $(TOP_MODULE).vcd

view: run
	gtkwave $(TOP_MODULE).vcd
