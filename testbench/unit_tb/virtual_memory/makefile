# testbench/unit_tb/virtual_memory/Makefile

ROOT := ../../..
BUILD := build

VERILATOR := verilator
GTKWAVE   := gtkwave

# Include paths (para `include "rtl_common.svh" y similares)
INCDIRS := -I$(ROOT)/includes -I$(ROOT)/rtl -I$(ROOT)/rtl/virtualmemory

# Verilator flags
VFLAGS := -O2 --sv --binary --trace --trace-structs \
          -Wall -Wno-UNUSED -Wno-UNDRIVEN -Wno-PINCONNECTEMPTY -Wno-fatal \
          $(INCDIRS)

# ---------------- Packages (ORDEN IMPORTA) ----------------
PKGS := \
  $(ROOT)/includes/pkg_riscv_instructions.sv \
  $(ROOT)/includes/pkg_virtual_memory.sv \
  $(ROOT)/includes/pkg_global_defs.sv

# ---------------- Interfaces VM ----------------
VM_IFACES := \
  $(ROOT)/rtl/virtualmemory/cpu_mmu_if.sv \
  $(ROOT)/rtl/virtualmemory/mmu_tlb_if.sv \
  $(ROOT)/rtl/virtualmemory/mmu_pw_if.sv \
  $(ROOT)/rtl/virtualmemory/pw_cache_if.sv

# ---------------- RTL blocks ----------------
TLB_RTL := $(ROOT)/rtl/virtualmemory/tlb.sv
PW_RTL  := $(ROOT)/rtl/virtualmemory/page_walker.sv
MMU_RTL := $(ROOT)/rtl/virtualmemory/mmu.sv

# ---------------- Testbenches (local) ----------------
TB_TLB := tb_tlb.sv
TB_PW  := tb_pw.sv
TB_MMU := tb_mmu.sv

# ---------------- Outputs ----------------
OBJ_TLB := $(BUILD)/obj_tlb
OBJ_PW  := $(BUILD)/obj_pw
OBJ_MMU := $(BUILD)/obj_mmu

EXE_TLB := $(OBJ_TLB)/Vtb_tlb
EXE_PW  := $(OBJ_PW)/Vtb_pw
EXE_MMU := $(OBJ_MMU)/Vtb_mmu

VCD_TLB := $(BUILD)/tb_tlb.vcd
VCD_PW  := $(BUILD)/tb_pw.vcd
VCD_MMU := $(BUILD)/tb_mmu.vcd

.PHONY: all tlb pw mmu wave_tlb wave_pw wave_mmu clean

all: tlb pw mmu

$(BUILD):
	mkdir -p $(BUILD)

# ---------------- TLB TB ----------------
tlb: $(BUILD)
	$(VERILATOR) $(VFLAGS) -Mdir $(OBJ_TLB) -o Vtb_tlb \
	  $(PKGS) $(VM_IFACES) $(TLB_RTL) $(TB_TLB)
	$(EXE_TLB)

wave_tlb: tlb
	$(GTKWAVE) $(VCD_TLB) &

# ---------------- Page Walker TB ----------------
pw: $(BUILD)
	$(VERILATOR) $(VFLAGS) -Mdir $(OBJ_PW) -o Vtb_pw \
	  $(PKGS) $(VM_IFACES) $(PW_RTL) $(TB_PW)
	$(EXE_PW)

wave_pw: pw
	$(GTKWAVE) $(VCD_PW) &

# ---------------- MMU TB ----------------
mmu: $(BUILD)
	$(VERILATOR) $(VFLAGS) -Mdir $(OBJ_MMU) -o Vtb_mmu \
	  $(PKGS) $(VM_IFACES) $(TLB_RTL) $(PW_RTL) $(MMU_RTL) $(TB_MMU)
	$(EXE_MMU)

wave_mmu: mmu
	$(GTKWAVE) $(VCD_MMU) &

clean:
	rm -rf $(BUILD)
