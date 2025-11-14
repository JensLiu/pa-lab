`timescale 1ps / 1ps
`include "rtl_common.svh"

module id_stage
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;
(
`ifdef REGISTER_FILE_EXPOSE_INTERNALS
    output reg_t DEBUG_regs[32],
`endif
    input clk_t clk,
    input id_control_t idControl,
    input if_id_regs_t ifIdRegs,
    output id_ex_regs_t idExRegs,
    output id_hints_t idHints
);

    inst_info_t instInfo;
    decoder decoder (
        .inst(ifIdRegs.inst),
        .info(instInfo)
    );

    // register file WITHOUT internal WB bypass
    word_t ID_oldRs1Data, ID_oldRs2Data;
    bool_t shuoldWrite = idControl.WB_isWriteback && !idControl.WB_hasException;
    register_file gpRegFile (
        .clk(clk),
`ifdef REGISTER_FILE_EXPOSE_INTERNALS
        .debug_regs(DEBUG_regs),
`endif
        // combinational logic
        .read_reg1(instInfo.rs1),
        .read_reg2(instInfo.rs2),
        .read_data1(ID_oldRs1Data),
        .read_data2(ID_oldRs2Data),
        // sequential logic
        .write_enable(shuoldWrite),
        .write_reg(idControl.WB_rd),
        .write_data(idControl.WB_rdData)
    );

    // EX, MEM, WB dependency resolver
    bool_t rs1ExDep, rs1MemDep, rs1WbDep, rs1HasDep, rs1ShouldHalt;
    assign rs1ExDep  = idControl.EX_rd == instInfo.rs1 && instInfo.rs1 != 5'd0;
    assign rs1MemDep = idControl.MEM_rd == instInfo.rs1 && instInfo.rs1 != 5'd0;
    assign rs1WbDep  = idControl.WB_rd == instInfo.rs1 && instInfo.rs1 != 5'd0;
    assign rs1HasDep = rs1ExDep || rs1MemDep || rs1WbDep;
    bool_t rs2ExDep, rs2MemDep, rs2WbDep, rs2HasDep, rs2ShouldHalt;
    assign rs2MemDep = idControl.MEM_rd == instInfo.rs2 && instInfo.rs2 != 5'd0;
    assign rs2ExDep = idControl.EX_rd == instInfo.rs2 && instInfo.rs2 != 5'd0;
    assign rs2WbDep = idControl.WB_rd == instInfo.rs2 && instInfo.rs2 != 5'd0;
    assign rs2HasDep = rs2ExDep || rs2MemDep || rs2WbDep;
    // NOTE: we should NOT allow `EX_isLoad` to bypass since the its `EX_aluResult`
    //       is the load address not the data
    assign rs1ShouldHalt = rs1ExDep && idControl.EX_isLoad;
    assign rs2ShouldHalt = rs2ExDep && idControl.EX_isLoad;
    // halt
    bool_t ID_shouldHalt;
    assign ID_shouldHalt = rs1ShouldHalt || rs2ShouldHalt;
    // EX, MEM, WB bypass
    word_t ID_rs1Data, ID_rs2Data;
    always_comb begin : id_conflict_resolver_bypass_or_else_halt
        if (rs1HasDep && !rs1ShouldHalt) begin
            // priority given to dependency in EX stage (newer value)
            if (rs1ExDep) begin
                ID_rs1Data = idControl.EX_aluResult;
            end else if (rs1MemDep) begin
                ID_rs1Data = idControl.MEM_memResult;
            end else begin
                assert (rs1WbDep)
                else $display("ID: UNREACHABLE DEPENDENCY");
                ID_rs1Data = idControl.WB_rdData;
            end
        end else begin
            ID_rs1Data = ID_oldRs1Data;
        end

        if (rs2HasDep && !rs2ShouldHalt) begin
            if (rs2ExDep) begin
                ID_rs2Data = idControl.EX_aluResult;
            end else if (rs2MemDep) begin
                ID_rs2Data = idControl.MEM_memResult;
            end else begin
                assert (rs2WbDep)
                else $display("ID: UNREACHABLE DEPENDENCY");
                ID_rs2Data = idControl.WB_rdData;
            end
        end else begin
            ID_rs2Data = ID_oldRs2Data;
        end

    end

    always_comb begin
        // propagate pipeline
        idExRegs.pc = ifIdRegs.pc;
        idExRegs.instInfo = instInfo;
`ifdef DEBUG_INST_INFO_EXTENSION
        idExRegs.instInfo.DEBUG_instID = ifIdRegs.DEBUG_instID;
`endif
        idExRegs.rs1Data = ID_rs1Data;
        idExRegs.rs2Data = ID_rs2Data;
        idExRegs.exceptions = ifIdRegs.exceptions;
        // emit signal
        idHints.shouldHalt = ID_shouldHalt;  // ask previous stages to halt
    end

endmodule
;
