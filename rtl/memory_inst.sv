`timescale 1ns / 1ps
`include "rtl_common.svh"

module memory_inst
    import pkg_global_defs::*;
    import pkg_riscv_instructions::*;
(
    // input clk_t                  clk,
    cache_request_if.slave cpuRequest
);
    byte_t mem  [INST_MEM_SIZE];

    addr_t addr;
    word_t inst;

    assign addr = cpuRequest.addr;
    assign cpuRequest.dataFromCache = inst;
    assign cpuRequest.ready = TRUE;
    assign cpuRequest.failed = FALSE;

    initial begin
        $display("INST_MEM_SIZE=%d", INST_MEM_SIZE);
        $readmemh("memory.hex", mem);
    end

    always_comb begin
        assert (addr < INST_MEM_SIZE)
        else $display("Invalid memory access @%h while max size is %h", addr, INST_MEM_SIZE);
        inst = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
    end

endmodule
