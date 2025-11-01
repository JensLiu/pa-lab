
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
    output if_id_regs_t ifIdRegs
);

    reg_t IF_pcQ;  // PC register

    reg_t IF_pcNext;

    always_comb begin
        // TODO exception handling
        if (ifControl.halt) begin
            IF_pcNext = IF_pcQ;
        end else if (ifControl.branchTaken) begin
            IF_pcNext = ifControl.pcBr;
        end else begin
            IF_pcNext = IF_pcQ + 4;
        end
    end

    always_ff @(posedge clk) begin
        IF_pcQ <= IF_pcNext;
    end

    instruction_t IF_inst;
    memory_inst memInst (
`ifdef INSTRUCTION_MEMORY_EXPOSE_INTERNALS
        .DEBUG_mem(DEBUG_mem),
`endif
        .clk(clk),
        .addr(IF_pcQ),
        .inst(IF_inst)
    );


    always_comb begin
        ifIdRegs.pc   = IF_pcQ;
        ifIdRegs.inst = IF_inst;
    end

endmodule
