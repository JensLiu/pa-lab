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
        imulHints.IMUL_resultTicket = stage4.ticket;
        imulHints.IMUL_result = stage4.A * stage4.B;
    end

    word_t DEBUGD_tick;
    always_ff @(posedge clk) begin : blockName
        DEBUGD_tick <= DEBUGD_tick + 1;
        if (stage0.ticket != ROB_TICKET_INVALID) begin
            `IMUL_PIPELINE_DEBUG_PRINT(
                ("[IMUL]: @%0d Stage 0 received IMUL ticket %0d: A=%h, B=%h",
                                  DEBUGD_tick,
                          stage0.ticket,
                          stage0.A,
                          stage0.B));
        end
        if (stage1.ticket != ROB_TICKET_INVALID) begin
            `IMUL_PIPELINE_DEBUG_PRINT(
                ("[IMUL]: @%0d Stage 1 processing IMUL ticket %0d", DEBUGD_tick, stage1.ticket));
        end
        if (stage2.ticket != ROB_TICKET_INVALID) begin
            `IMUL_PIPELINE_DEBUG_PRINT(
                ("[IMUL]: @%0d Stage 2 processing IMUL ticket %0d", DEBUGD_tick, stage2.ticket));
        end
        if (stage3.ticket != ROB_TICKET_INVALID) begin
            `IMUL_PIPELINE_DEBUG_PRINT(
                ("[IMUL]: @%0d Stage 3 processing IMUL ticket %0d", DEBUGD_tick, stage3.ticket));
        end
        if (stage4.ticket != ROB_TICKET_INVALID) begin
            `IMUL_PIPELINE_DEBUG_PRINT(
                ("[IMUL]: @%0d Stage 4 completing IMUL ticket %0d: A=%h, B=%h, Result=%h",
                                  DEBUGD_tick,
                          stage4.ticket,
                          stage4.A,
                          stage4.B,
                          stage4.A * stage4.B));
        end
    end

endmodule
