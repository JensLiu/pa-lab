
# Generic Makefile for tests
# - Compiles each test subdirectory into a RISC-V firmware ELF and then
#   converts it to Intel HEX and Verilog MEM (firmware.mem) inside that
#   test directory.
# - Builds a host-side `sim_main` from `sim_main.cpp` for local testing.

COMPILER  ?= riscv64-unknown-elf-gcc
OBJCOPY   ?= riscv64-unknown-elf-objcopy
OBJDUMP   ?= riscv64-unknown-elf-objdump
ARCH_FLAGS ?= -march=rv32im -mabi=ilp32
LIB_FLAGS  ?= -ffreestanding -nostdlib

CXX      ?= g++
# Ensure the host C++ build can find headers in the `sim` helper directory
CXXFLAGS ?= -std=c++17 -I.. -I../sim -O2

FIRMWARE_LINKER ?= ../../firmware/linker.ld

## Collect test directories (directories directly under this folder)
## Exclude the `build` directory which is used for intermediate objects
TEST_DIRS := $(filter-out build,$(shell for d in $(wildcard */); do \
	if [ -d "$$d" ] && [ -f "$$d/code.asm" ] && [ -f "$$d/result_check" ]; then \
		echo "$${d%/}"; \
	fi; \
done))

VERILATOR_UNIQUE_FLAGS = -x-assign unique -x-initial unique
VERILATOR_BUILD_FLAGS = --cc -exe --main --timing --build --exe -j 0
VERILATOR_TRACE_FLAGS = --trace-fst --trace-params --trace-structs --trace-underscore
VERILATOR_FLAGS = --sv --public -CFLAGS -fcoroutines "-Iobj_dir"  $(VERILATOR_UNIQUE_FLAGS) $(VERILATOR_TRACE_FLAGS) $(VERILATOR_BUILD_FLAGS) --timing
SIM_CPP = sim_main.cpp
BASE_DIR = ../..

.PHONY: all tests test_driver clean

all: tests test_driver run

# build all tests -> each produces <test>/inst.mem (verilog format copied to test root)
tests: $(patsubst %, %/inst.mem, $(TEST_DIRS))

# Per-test rule: build firmware.elf, produce .hex, .mem and .asm
# This recipe is intentionally conservative and compiles any .c/.S/.s/.asm
# files found in the test directory.

%/inst.mem:
	@echo "==> Building test: $(@D)"
	@mkdir -p $(@D)/build
		@set -e; \
		for src in $(@D)/*.c; do \
			if [ -f $$src ]; then \
				OBJ=$(@D)/build/$$(basename $$src).o; \
				$(COMPILER) -c $(ARCH_FLAGS) $(LIB_FLAGS) -o $$OBJ $$src 2>/dev/null; \
			fi; \
		done; \
		for asm in $(@D)/*.S $(@D)/*.s $(@D)/code.asm; do \
			if [ -f $$asm ]; then \
				OBJ=$(@D)/build/$$(basename $$asm).o; \
				case "$$asm" in \
					*.asm) $(COMPILER) -c $(ARCH_FLAGS) -x assembler -o $$OBJ $$asm 2>/dev/null ;; \
					*) $(COMPILER) -c $(ARCH_FLAGS) -o $$OBJ $$asm 2>/dev/null ;; \
				esac; \
			fi; \
		done; \
	# link all objects produced for this test (test must provide its own entry)
	# try to link all objects; if the glob doesn't match or linking fails,
	# emit a helpful message and fail
	$(COMPILER) $(ARCH_FLAGS) -nostdlib -nostartfiles -T $(FIRMWARE_LINKER) -o $(@D)/build/inst.elf $(@D)/build/*.o || { \
		echo "  ERROR: Failed to link objects for $(@D) - ensure the test provides .c or .S/.asm sources"; \
		exit 1; \
	}
	# create hex, verilog mem and asm listing inside the per-test build folder
	$(OBJCOPY) -O ihex $(@D)/build/inst.elf $(@D)/build/inst.hex
	$(OBJCOPY) -I ihex -O verilog $(@D)/build/inst.hex $(@D)/build/verilog.hex
	$(OBJDUMP) -D $(@D)/build/inst.elf > $(@D)/build/inst.asm
	# copy only the verilog-format mem into the test root (user requested)
	cp $(@D)/build/verilog.hex $(@D)/memory.hex
	@echo "  -> $(@D)/memory.hex"

# Build sim_main
test_driver:
	@echo "==> Building host sim_main"
	# Use absolute include paths so the generated obj_dir Makefile (which runs
	# compilation from inside obj_dir) can find headers like pipeline_stage_logger.hpp
	verilator -sv $(VERILATOR_TRACE_FLAGS) --cc --exe --build -j 0 \
	--top-module datapath_pipelined \
	-CFLAGS "-I$(abspath obj_dir) -I$(abspath ../../sim)" \
	-I$(abspath ${BASE_DIR}/includes) -I$(abspath ${BASE_DIR}/rtl) \
	-I$(abspath ${BASE_DIR}/rtl/datapath) -I$(abspath ${BASE_DIR}/rtl/cache) \
	-I$(abspath ${BASE_DIR}/rtl/memory) -I$(abspath ${BASE_DIR}/rtl/reorder_buffer) \
	-I$(abspath ${BASE_DIR}/rtl/store_buffer) -I$(abspath obj_dir) \
	${BASE_DIR}/includes/pkg_riscv_instructions.sv \
	${BASE_DIR}/includes/pkg_global_defs.sv \
	${BASE_DIR}/rtl/*.sv \
	${BASE_DIR}/rtl/datapath/*.sv \
	${BASE_DIR}/rtl/cache/*.sv \
	${BASE_DIR}/rtl/memory/*.sv \
	${BASE_DIR}/rtl/reorder_buffer/*.sv \
	${BASE_DIR}/rtl/store_buffer/*.sv \
	sim_main.cpp
	@echo "  -> ./sim_main"

run: test_driver tests
	rm -f */failed
	@echo "==> Running simulation"
	./obj_dir/Vdatapath_pipelined

clean:
	@echo "Cleaning build artifacts..."
	-rm -rf */build
	-rm -f */memory.hex
	-rm -f memory.hex
	-rm -f */*.fst
	-rm -f */failed
	-rm -rf obj_dir
	-rm -f sim_main
	-rm -f */*.log
