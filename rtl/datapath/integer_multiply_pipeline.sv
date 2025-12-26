`include "rtl_common.svh"

import pkg_global_defs::*;

module integer_multiply_pipeline (
    input logic clk,
    input id_imul_regs_t idImulRegs,
    input imul_control_t imulControl,
    output imul_hints_t imulHints
);

    id_imul_regs_t stage0, stage1, stage2, stage3, stage4;
    initial begin
        stage0.ticket = ROB_TICKET_INVALID;
        stage1.ticket = ROB_TICKET_INVALID;
        stage2.ticket = ROB_TICKET_INVALID;
        stage3.ticket = ROB_TICKET_INVALID;
        stage4.ticket = ROB_TICKET_INVALID;
    end

    always_ff @(posedge clk) begin : Pipeline
        stage0 <= idImulRegs;
        stage1 <= stage0;
        stage2 <= stage1;
        stage3 <= stage2;
        stage4 <= stage3;
    end

    always_comb begin
        // $display("stage0.ticket=%0d", stage0.ticket);
        // $display("stage1.ticket=%0d", stage1.ticket);
        // $display("stage2.ticket=%0d", stage2.ticket);
        // $display("stage3.ticket=%0d", stage3.ticket);
        // $display("stage4.ticket=%0d", stage4.ticket);
        imulHints.IMUL_resultTicket = stage4.ticket;
        imulHints.IMUL_result = stage4.A * stage4.B;
    end

endmodule
