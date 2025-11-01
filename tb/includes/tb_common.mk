# Common Makefile variables for testbenches

RTL_DIR = $(BASE_DIR)/rtl
RTL_INCLUDES_DIR = $(BASE_DIR)/includes
TB_INCLUDES_DIR = ${BASE_DIR}/tb/includes
VERILATOR_UNIQUE_FLAGS = -x-assign unique -x-initial unique
VERILATOR_TRACE_FLAGS = --trace-fst
VERILATOR_BUILD_FLAGS = --cc -exe --main --timing --build --exe -j 0

VERILATOR_FLAGS = -CFLAGS -fcoroutines $(VERILATOR_UNIQUE_FLAGS) $(VERILATOR_TRACE_FLAGS) $(VERILATOR_BUILD_FLAGS) --timing
PACKAGES = ${RTL_INCLUDES_DIR}/pkg_global_defs.sv ${RTL_INCLUDES_DIR}/pkg_riscv_instructions.sv
INCLUDE_FLAGS = -I${RTL_INCLUDES_DIR} -I${TB_INCLUDES_DIR}

# common in all testbench Makefiles
SOURCES = $(PACKAGES) ${RTL_SOURCES} ./$(TOP_MODULE).sv

.PHONY: all build run clean

all: build run

build:
	@verilator $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) $(SOURCES) ${INCLUDE_FLAGS}

run: build
	@./obj_dir/V$(TOP_MODULE)

clean:
	@rm -rf obj_dir $(TOP_MODULE).vcd

wave: run
	gtkwave $(TOP_MODULE).vcd
