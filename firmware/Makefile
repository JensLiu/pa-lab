# Makefile for riscv baremetal machine

COMPILER = riscv64-unknown-elf-gcc

ARCH_FLAGS = -march=rv32im -mabi=ilp32 
ARCH_FLAGS += -ffreestanding -nostdlib

all: build intel-hex verilog-hex asm

build:
	@$(COMPILER) -c -march=rv32im -mabi=ilp32 \
							-ffreestanding -nostdlib \
	 						-o main.o main.c
	@$(COMPILER) -c -march=rv32im -mabi=ilp32 \
							-o start.o start.S
	@$(COMPILER) -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles \
							-T linker.ld \
							-o firmware.elf start.o main.o

intel-hex: build
	@riscv64-unknown-elf-objcopy -O ihex firmware.elf firmware.hex

verilog-hex: intel-hex
	@objcopy -I ihex -O verilog firmware.hex firmware.mem

asm: build
	@riscv64-unknown-elf-objdump -D firmware.elf > firmware.asm

datapath: verilog-hex asm
	@cp firmware.mem ../tb/tb_datapath/inst_mem.hex
	@cd ../tb/tb_datapath && make

clean:
	@rm -rf *.o *.asm *.elf *.hex *.bin *.mem
