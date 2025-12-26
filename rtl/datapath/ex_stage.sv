`timescale 1ps / 1ps

`include "rtl_common.svh"

module ex_stage
    import pkg_global_defs::*;
    import pkg_riscv_instructions::*;
(
    input clk_t clk,
    input id_ex_regs_t idExRegs,
    input ex_control_t exControl,
    output ex_mem_regs_t exMemRegs,
    output ex_hints_t exHints
);
    word_t EX_ticket = idExRegs.ticket;
    addr_t EX_pc = idExRegs.pc;
    inst_info_t EX_instInfo;
    assign EX_instInfo = idExRegs.instInfo;
    word_t EX_rs1Data, EX_rs2Data;
    assign EX_rs1Data = idExRegs.rs1Data;
    assign EX_rs2Data = idExRegs.rs2Data;

    word_t EX_aluA;
    word_t EX_aluB;
    assign EX_aluA = EX_instInfo.aluUsePCAsRs1 ? EX_pc : EX_rs1Data;
    assign EX_aluB = EX_instInfo.aluUseImmAsRs2 ? EX_instInfo.imm : EX_rs2Data;

    always_comb begin
        if (EX_instInfo.branchType != BR_INVALID) begin
            // normal branch and unconditioanl branch all uses relative offset
            assert (EX_instInfo.aluUseImmAsRs2);
            assert (EX_aluOp == ALU_ADD);
            // if (EX_instInfo.branchType == BR_UNCOND) begin
            //     assert (EX_instInfo.aluUsePCAsRs1);
            // end
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
    comparator cmp (
        .A(EX_rs1Data),
        .B(EX_rs2Data),
        .isSigned(EX_instInfo.cmpIsSigned),
        .res(EX_cmpResult)
    );

    // Branch
    bool_t EX_shouldBranch;
    always_comb begin
        case (EX_instInfo.branchType)
            BR_BEQ: EX_shouldBranch = EX_cmpResult.eq;
            BR_BNE: EX_shouldBranch = !EX_cmpResult.eq;
            BR_BLT, BR_BLTU: EX_shouldBranch = EX_cmpResult.lt;
            BR_BGE, BR_BGEU: EX_shouldBranch = EX_cmpResult.eq | EX_cmpResult.gt;
            BR_UNCOND: EX_shouldBranch = TRUE;
            default: EX_shouldBranch = FALSE;
        endcase
    end

    // NOTE: the "expected ALU result" is emitted and passed down since
    //       `jal` has the semantics of rd <- PC + 4
    word_t EX_expectedAluResult;
    assign EX_expectedAluResult = EX_instInfo.branchType == BR_UNCOND ? EX_pc + 4 : EX_aluResult;

    always_comb begin
        // propagate
        exMemRegs.ticket = EX_ticket;
        exMemRegs.pc = idExRegs.pc;
        exMemRegs.instInfo = idExRegs.instInfo;
        exMemRegs.aluResult = EX_expectedAluResult;
        exMemRegs.stData = EX_instInfo.isStore ? EX_rs2Data : IMM_32_WHATEVER;

        // emit hints
        exHints.EX_ticket = EX_ticket;
        exHints.EX_excaptions = '0;  // TODO: add exceptions
        exHints.EX_isWriteback = EX_instInfo.isWriteback;
        exHints.EX_isLoad = EX_instInfo.isLoad;
        exHints.EX_isStore = EX_instInfo.isStore;
        exHints.EX_isBranch = EX_instInfo.branchType != BR_INVALID;
        // branch hints
        exHints.EX_shouldBranch = EX_shouldBranch;
        exHints.EX_pcBr = EX_aluResult;
        // writeback hints
        exHints.EX_rd = EX_instInfo.rd;
        // arithmetic hints
        exHints.EX_aluResult = EX_expectedAluResult;

    end

    logic [31:0] DEBUG_tick;
    always_ff @(posedge clk) begin
        DEBUG_tick <= DEBUG_tick + 1;
    end

    always_ff @(posedge clk) begin
        `EX_STAGE_DEBUG_PRINT(("[EX]: @%0d ticket %0d", DEBUG_tick, EX_ticket));
    end

endmodule
