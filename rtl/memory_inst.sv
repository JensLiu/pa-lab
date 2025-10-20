`timescale 1ns / 1ps

module memory_inst 
import pkg_global_defs::*;
import pkg_riscv_instructions::*;
(
    input  clk_t         clk,
    input  addr_t        addr,
    output instruction_t inst
);

    parameter N_INSTS = 4 * 4095;
    byte_t mem[N_INSTS:0];

    initial begin
        $readmemh("inst_mem.hex", mem);
    end

    always_ff @(posedge clk) begin
        inst <= {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
    end

endmodule
