# Makefile for riscv baremetal machine

COMPILER = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
OBJDUMP = riscv64-unknown-elf-objdump

ARCH_FLAGS = -march=rv32im -mabi=ilp32
LIB_FLAGS = -ffreestanding -nostdlib

all: build intel-hex verilog-hex asm

build:
	@$(COMPILER) -c $(ARCH_FLAGS) $(LIB_FLAGS) -o main.o main.c
	@$(COMPILER) -c $(ARCH_FLAGS) -o start.o start.S
	@$(COMPILER) $(ARCH_FLAGS) -nostdlib -nostartfiles \
							-T linker.ld \
							-o firmware.elf start.o main.o

intel-hex: build
	@$(OBJCOPY) -O ihex firmware.elf firmware.hex

verilog-hex: intel-hex
	@$(OBJCOPY) -I ihex -O verilog firmware.hex firmware.mem

asm: build
	@$(OBJDUMP) -D firmware.elf > firmware.asm

datapath: verilog-hex asm
	@cp firmware.mem ../sim/memory.hex
	@cd ../sim && make

clean:
	@rm -rf *.o *.asm *.elf *.hex *.bin *.mem
