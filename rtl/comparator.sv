`timescale 1ns / 1ps
`include "rtl_common.svh"

module comparator
    import pkg_global_defs::*;
(
    input imm_arith_t A,
    input imm_arith_t B,
    input bool_t isSigned,
    output cmp_result_t res
);

    assign res.eq = A == B;
    assign res.lt = isSigned ? $signed(A) < $signed(B) : A < B;
    assign res.gt = isSigned ? $signed(A) > $signed(B) : A > B;

    // always_comb begin : DebugPrint
    //     if (A != 'h12345678 || B != 'h12345678) begin
    //         // skip printing magic numbers
    //         if (isSigned) begin
    //             $display("[CMP]: Comparing signed %0h and %0h => eq: %0b, lt: %0b, gt: %0b", A, B,
    //                      res.eq, res.lt, res.gt);
    //         end else begin
    //             $display("[CMP]: Comparing unsigned %0h and %0h => eq: %0b, lt: %0b, gt: %0b", A,
    //                      B, res.eq, res.lt, res.gt);
    //         end
    //     end
    // end

endmodule
;
