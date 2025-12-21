`include "rtl_common.svh"

import pkg_global_defs::*;

module integer_multiply_pipeline (
    input logic clk,
    input id_imul_regs_t idImulRegs,
    input imul_control_t imulControl,
    output imul_hints_t imulHints
);

    id_imul_regs_t stage0, stage1, stage2, stage3, stage4;
    always_ff @(posedge clk) begin : Pipeline
        stage0 <= idImulRegs;
        stage1 <= stage0;
        stage2 <= stage1;
        stage3 <= stage2;
        stage4 <= stage3;
    end

    always_comb begin
        imulHints.IMUL_resultTicket = stage4.ticket;
        imulHints.IMUL_result = stage4.A * stage4.B;
    end

endmodule
