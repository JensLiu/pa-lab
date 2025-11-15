`timescale 1ps / 1ps
`include "rtl_common.svh"

module if_stage
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;
(
`ifdef INSTRUCTION_MEMORY_EXPOSE_INTERNALS
    output byte_t       DEBUG_mem[INST_MEM_SIZE],
`endif
    input  clk_t        clk,
    input  if_control_t ifControl,
    output if_id_regs_t ifIdRegs,
    output if_hints_t   ifHints,
    // interface to the external cache
    cache_request_if.master cacheRequest
);

    reg_t IF_pcQ;  // PC register

    initial begin
        IF_pcQ = START_ADDRESS;
        $display("Start executing at %h", IF_pcQ);
    end

    always_ff @(posedge clk) begin
        // TODO exception handling
        if (ifControl.halt) begin
            IF_pcQ <= IF_pcQ;
        end else if (ifControl.branchTaken) begin
            IF_pcQ <= ifControl.pcBr;
        end else begin
            IF_pcQ <= IF_pcQ + 4;
        end
    end

    instruction_t IF_inst;
    logic cacheRequestDone;
    always_comb begin
        IF_inst = cacheRequest.dataFromCache;
        cacheRequest.addr = IF_pcQ;
        cacheRequest.isRead = TRUE;
        cacheRequestDone = cacheRequest.ready;
    end


    always_comb begin
        ifIdRegs.pc   = IF_pcQ;
        ifIdRegs.inst = IF_inst;
        ifHints.shouldHalt = !cacheRequestDone;
`ifdef DEBUG_INST_INFO_EXTENSION
        ifIdRegs.DEBUG_instID = DEBUG_nextInstID;
`endif
    end

`ifdef DEBUG_INST_INFO_EXTENSION
    word_t DEBUG_nextInstID;
    initial DEBUG_nextInstID = 0;
    always_ff @(posedge clk) begin
        if (!ifControl.halt) begin
            DEBUG_nextInstID <= DEBUG_nextInstID + 1;
        end
    end
`endif

endmodule
