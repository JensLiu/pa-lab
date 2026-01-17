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
        wbHints.WB_commitTicket = wbControl.ROB_commitTicket;
        wbHints.WB_commitFinished = TRUE;
        wbHints.shouldHalt = FALSE;  // when halting, the WB stage DOES NOT accept commits
        wbHints.WB_jump = FALSE;
        wbHints.WB_jumpPC = IMM_32_WHATEVER;
        wbHints.WB_isWriteback = FALSE;
        wbHints.WB_hasException = FALSE;
        wbHints.WB_rd = '0;
        wbHints.WB_rdData = '0;
        if (wbControl.ROB_commitTicket == ROB_TICKET_INVALID) begin
            `WB_STAGE_DEBUG_PRINT(("[WB]: @%0d No valid commit in this cycle", DEBUGD_tick));
        end else begin
            if (wbControl.ROB_commitException != '0) begin
                `WB_STAGE_DEBUG_PRINT(
                    ("[WB]: @%0d Handling excaption %h from ROB ticket %0d",
                                              DEBUGD_tick,
                                      wbControl.ROB_commitException,
                                      wbControl.ROB_commitTicket));
                // handle excaption
                wbHints.WB_jump = TRUE;
                wbHints.WB_jumpPC = 32'h0000_ffff;
                wbHints.shouldHalt = wbControl.IF_cannotJump;
                wbHints.WB_hasException = TRUE;
                $display("Excaption handler is not implemented");
                assert (FALSE);
            end else begin  // no exceptions, normal commit
                if (wbControl.ROB_commitIsBranch) begin
                    if (wbControl.ROB_commitShouldBranch) begin
                        wbHints.WB_jump = TRUE;
                        wbHints.WB_jumpPC = wbControl.ROB_commitBranchPCVirtAddr;
                        // NOTE: hold back when IF cannot jump
                        wbHints.shouldHalt = wbControl.IF_cannotJump;
                        if (wbControl.IF_cannotJump) begin
                            wbHints.WB_commitFinished = FALSE;
                            `WB_STAGE_DEBUG_PRINT(
                                ("[WB]: @%0d Branch to %h from ROB ticket %0d but IF cannot jump, holding back",
                                              DEBUGD_tick,
                                              wbControl.ROB_commitBranchPCVirtAddr,
                                              wbControl.ROB_commitTicket));
                        end else begin
                            `WB_STAGE_DEBUG_PRINT(
                                ("[WB]: @%0d Branch taken to %h from ROB ticket %0d",
                                              DEBUGD_tick,
                                              wbControl.ROB_commitBranchPCVirtAddr,
                                              wbControl.ROB_commitTicket));
                        end
                    end else begin
                        `WB_STAGE_DEBUG_PRINT(
                            ("[WB]: @%0d Branch not taken from ROB ticket %0d",
                                              DEBUGD_tick,
                                              wbControl.ROB_commitTicket));
                    end
                end
                if (wbControl.ROB_commitIsWriteback) begin
                    wbHints.WB_isWriteback = TRUE;
                    wbHints.WB_rd = wbControl.ROB_commitRd;
                    wbHints.WB_rdData = wbControl.ROB_commitRdData;
                    `WB_STAGE_DEBUG_PRINT(
                        ("[WB]: @%0d Writeback data valid for ROB ticket %0d, performing writeback",
                                              DEBUGD_tick,
                                              wbControl.ROB_commitTicket));
                end
                if (wbControl.ROB_commitIsStore) begin
                    if (wbControl.ROB_commitStoreComplete) begin
                        `WB_STAGE_DEBUG_PRINT(
                            ("[WB]: @%0d Store completed for ROB ticket %0d",
                                                  DEBUGD_tick,
                                                  wbControl.ROB_commitTicket));
                    end else begin
                        // hold back when store not completed
                        wbHints.WB_commitFinished = FALSE;
                        `WB_STAGE_DEBUG_PRINT(
                            ("[WB]: @%0d Store NOT completed for ROB ticket %0d",
                                                  DEBUGD_tick,
                                                  wbControl.ROB_commitTicket));
                    end
                end
            end
        end
    end

    always_comb begin : Hints
    end

    word_t DEBUGD_tick;
    always_ff @(posedge clk) begin
        DEBUGD_tick <= DEBUGD_tick + 1;
    end

endmodule
