`include "rtl_common.svh"

import pkg_global_defs::*;

typedef struct {
    imm_arith_t A;
    imm_arith_t B;
} multiply_pipeline_context_t;

module integer_multiply_pipeline (
    input logic clk,
    input multiply_pipeline_context_t contextIn,
    output multiply_pipeline_context_t contextOut,
    output imm_arith_t Y
);

    multiply_pipeline_context_t stage0, stage1, stage2, stage3, stage4;

    always_ff @(posedge clk) begin : Pipeline
        stage0 <= contextIn;
        stage1 <= stage0;
        stage2 <= stage1;
        stage3 <= stage2;
        stage4 <= stage3;
        Y <= stage4.A * stage4.B;
    end

endmodule
