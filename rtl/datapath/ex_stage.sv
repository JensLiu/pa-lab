`timescale 1ps / 1ps

`include "rtl_common.svh"

module ex_stage
    import pkg_global_defs::*;
    import pkg_riscv_instructions::*;
(
    // input clk_t clk,
    input id_ex_regs_t idExRegs,
    input ex_control_t exControl,
    output ex_mem_regs_t exMemRegs,
    output ex_hints_t exHints
);
    addr_t EX_pc = idExRegs.pc;
    inst_info_t EX_instInfo = idExRegs.instInfo;
    word_t EX_rs1Data = idExRegs.rs1Data, EX_rs2Data = idExRegs.rs2Data;

    word_t EX_aluA;
    word_t EX_aluB;
    always_comb begin
        if (EX_instInfo.branchType == BR_INVALID) begin
            // normal operations
            EX_aluA = EX_rs1Data;
            EX_aluB = EX_instInfo.aluUseImmAsRs2 ? EX_instInfo.imm : EX_rs2Data;
        end else begin
            // normal branch and unconditioanl branch all uses relative offset
            EX_aluA = EX_pc;  // PC
            assert (EX_instInfo.aluUseImmAsRs2);
            assert (EX_aluOp == ALU_ADD);
            EX_aluB = EX_instInfo.imm;  // OFFSET
            // NOTE: for `jal` instrutions, we shuold write PC + 4 to the register
            //       it is handled by faking the aluResult
        end
    end

    always_comb begin
        if (EX_instInfo.branchType != BR_UNCOND && EX_instInfo.branchType != BR_INVALID) begin
            assert (EX_instInfo.aluUseImmAsRs2 == TRUE)
            else $display("Error: Conditional Branch should use offset");
        end
    end


    alu_op_t EX_aluOp = EX_instInfo.aluOp;
    word_t   EX_aluResult;
    alu alu (
        .A(EX_aluA),
        .B(EX_aluB),
        .aluOp(EX_aluOp),
        .Y(EX_aluResult)
    );

    // CMP
    cmp_result_t EX_cmpResult;
    imm_arith_t EX_cmpA = EX_rs1Data;
    imm_arith_t EX_cmpB = EX_rs2Data;
    bool_t EX_cmpIsSigned = EX_instInfo.cmpIsSigned;
    comparator cmp (
        .A(EX_cmpA),
        .B(EX_cmpB),
        .isSigned(EX_cmpIsSigned),
        .res(EX_cmpResult)
    );

    // Branch
    bool_t EX_branchTaken;
    always_comb begin
        case (EX_instInfo.branchType)
            BR_BEQ: EX_branchTaken = EX_cmpResult.eq;
            BR_BNE: EX_branchTaken = !EX_cmpResult.eq;
            BR_BLT, BR_BLTU: EX_branchTaken = EX_cmpResult.lt;
            BR_BGE, BR_BGEU: EX_branchTaken = EX_cmpResult.eq | EX_cmpResult.gt;
            BR_UNCOND: EX_branchTaken = TRUE;
            default: EX_branchTaken = FALSE;
        endcase
    end

    addr_t EX_pcBr = EX_aluResult;

    // NOTE: the "expected ALU result" is emitted and passed down since
    //       `jal` has the semantics of rd <- PC + 4
    word_t EX_expectedAluResult;
    assign EX_expectedAluResult = EX_instInfo.branchType == BR_UNCOND ? EX_pc + 4 : EX_aluResult;

    always_comb begin
        // propagate
        exMemRegs.pc = idExRegs.pc;
        exMemRegs.instInfo = idExRegs.instInfo;
        exMemRegs.aluResult = EX_expectedAluResult;
        exMemRegs.stData = EX_instInfo.isStore ? EX_rs2Data : IMM_32_WHATEVER;
        // emit signal
        exHints.EX_branchTaken = EX_branchTaken;
        exHints.EX_pcBr = EX_pcBr;
        exHints.EX_isWriteback = EX_instInfo.isWriteback;
        exHints.EX_rd = EX_instInfo.rd;
        exHints.EX_isLoad = EX_instInfo.isLoad;
        exHints.EX_aluResult = EX_expectedAluResult;
    end


endmodule
;
