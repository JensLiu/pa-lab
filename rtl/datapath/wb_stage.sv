`timescale 1ps / 1ps

module wb_stage
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;
(
    input  wb_control_t wbControl,  // listens to ROB commit info
    output wb_hints_t   wbHints
);
    // we just simply forwarding the ROB commit info to WB hints
    // TODO: check exceptions and handle jump
    always_comb begin
        assert (wbHints.ROB_oldestException == '0);  // assert no exceptions
        // TODO: handle branch
        wbHints.WB_isWriteback = wbControl.ROB_oldestIsWriteback;
        if (wbControl.ROB_RdDataValid) begin
            wbHints.WB_rd = wbControl.ROB_oldestRd;
            wbHints.WB_rdData = wbControl.ROB_oldestRdData;
        end else begin
            // maybe the oldest entry does not have valid data (e.g., load not ready)
            // we shouldn't forward writeback
            wbHints.WB_rd = '0;
            wbHints.WB_rdData = '0;
        end
    end

endmodule
