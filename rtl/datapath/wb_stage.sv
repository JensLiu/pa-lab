`timescale 1ps / 1ps


module wb_stage
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;
(
    input clk_t clk,
    input wb_control_t wbControl,  // listens to ROB commit info
    output wb_hints_t wbHints
);
    // we just simply forwarding the ROB commit info to WB hints
    // TODO: check exceptions and handle jump
    always_comb begin
        wbHints.shouldHalt = FALSE;  // when halting, the WB stage DOES NOT accept commits
        wbHints.WB_jump = FALSE;
        wbHints.WB_jumpPC = IMM_32_WHATEVER;
        wbHints.WB_rdData = IMM_32_WHATEVER;
        wbHints.WB_hasException = FALSE;
        wbHints.WB_rd = '0;
        wbHints.WB_rdData = '0;
        if (wbControl.ROB_commitEntryValid) begin
            if (wbControl.ROB_commitException != '0) begin
                `WB_STAGE_DEBUG_PRINT(
                    ("[WB]: @%0d Handling excaption %h from ROB ticket %0d",
                                              DEBUGD_tick,
                                      wbControl.ROB_commitException,
                                      wbControl.DEBUG_ROB_commitTicket));
                // handle excaption
                wbHints.WB_jump = TRUE;
                wbHints.WB_jumpPC = 32'h0000_ffff;
                wbHints.shouldHalt = wbControl.IF_cannotJump;
                wbHints.WB_hasException = TRUE;
                $display("Excaption handler is not implemented");
                assert (FALSE);
            end else begin
                `WB_STAGE_DEBUG_PRINT(
                    ("[WB]: @%0d Committing ROB ticket %0d",
                                              DEBUGD_tick,
                                              wbControl.DEBUG_ROB_commitTicket));
                if (wbControl.ROB_commitIsBranch) begin
                    if (wbControl.ROB_commitShouldBranch) begin
                        `WB_STAGE_DEBUG_PRINT(
                            ("[WB]: @%0d Branch taken to %h from ROB ticket %0d",
                                              DEBUGD_tick,
                                              wbControl.ROB_commitBranchPCVirtAddr,
                                              wbControl.DEBUG_ROB_commitTicket));
                        wbHints.WB_jump = TRUE;
                        wbHints.WB_jumpPC = wbControl.ROB_commitBranchPCVirtAddr;
                        wbHints.shouldHalt = wbControl.IF_cannotJump;
                    end
                end else if (wbControl.ROB_commitIsWriteback) begin
                    `WB_STAGE_DEBUG_PRINT(
                        ("[WB]: @%0d Writeback rd=%0d data=%h from ROB ticket %0d",
                                          DEBUGD_tick,
                                          wbControl.ROB_commitRd,
                                          wbControl.ROB_commitRdData,
                                          wbControl.DEBUG_ROB_commitTicket));
                    wbHints.WB_isWriteback = TRUE;
                    if (wbControl.ROB_commitRdDataValid) begin
                        wbHints.WB_rd = wbControl.ROB_commitRd;
                        wbHints.WB_rdData = wbControl.ROB_commitRdData;
                    end else begin
                        // maybe the oldest entry does not have valid data (e.g., load not ready)
                        // we shouldn't forward writeback
                    end
                end
            end
        end
    end

    word_t DEBUGD_tick;
    always_ff @(posedge clk) begin
        DEBUGD_tick <= DEBUGD_tick + 1;
    end

endmodule
