`timescale 1ns / 1ps
`include "../includes/includes.sv"

module alu
    import pkg_global_defs::*;
(
    input  imm_arith_t A,       // input 1
    input  imm_arith_t B,       // input 2
    input  alu_op_t    aluOp,  // instruction
    output imm_arith_t Y        // output
    // status registers
    // output alu_flags_t        flags
);
    // assign flags.zero = y == 0;

    always_comb begin
        case (aluOp)
            ALU_ADD:  Y = A + B;
            ALU_SUB:  Y = A - B;
            ALU_INC:  Y = A + 1;
            ALU_DEC:  Y = A - 1;
            ALU_NOT:  Y = ~A;
            ALU_AND:  Y = A & B;
            ALU_OR:   Y = A | B;
            ALU_XOR:  Y = (A & ~B) | (~A | B);
            ALU_SLL:  Y = A << B;
            ALU_SLT:  Y = ($signed(A) < $signed(B)) ? A : B;
            ALU_SLTU: Y = (A < B) ? A : B;
            ALU_SRL:  Y = A >> B;
            ALU_SRA:  Y = $signed(A) >>> B;
            default:  Y = IMM_32_WHATEVER;
        endcase
    end

endmodule
