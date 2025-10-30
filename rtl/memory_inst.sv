`timescale 1ns / 1ps
`include "rtl_common.svh"

module memory_inst
    import pkg_global_defs::*;
    import pkg_riscv_instructions::*;
(
`ifdef INSTRUCTION_MEMORY_EXPOSE_INTERNALS
    output byte_t        DEBUG_mem[INST_MEM_SIZE],
`endif
    input  clk_t         clk,
    input  addr_t        addr,
    output instruction_t inst
);
    byte_t mem[INST_MEM_SIZE];

    initial begin
        $readmemh("inst_mem.hex", mem);
        // for (int i = 0; i < 100; i++) begin
        //     if (i != 0 && i % 4 == 0) begin
        //         $write("\n");
        //     end
        //     $write("%h ", mem[i]);
        // end
    end

    always_comb begin
        inst = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
`ifdef INSTRUCTION_MEMORY_EXPOSE_INTERNALS
        // DEBUG_mem <= mem;
`endif
    end

endmodule
