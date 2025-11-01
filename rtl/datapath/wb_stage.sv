`timescale 1ps / 1ps

module wb_stage
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;
(
    // input clk_t clk,
    input mem_wb_regs_t memWbRegs,
    input wb_control_t wbControl,
    output wb_hints_t wbHints
);

    always_comb begin
        wbHints.WB_rd = memWbRegs.instInfo.rd;
        wbHints.WB_isWriteback = memWbRegs.instInfo.isWriteback;
        wbHints.WB_rdData = memWbRegs.memResult;
    end

endmodule
