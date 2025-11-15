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
    assign res.gt = isSigned ? $signed(A) > $signed(B) : A < B;

endmodule;
