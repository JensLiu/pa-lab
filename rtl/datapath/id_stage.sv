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
    output id_hints_t idHints,
    bypass_network_query_if.master bypassQuery
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


    assign bypassQuery.rs1 = instInfo.rs1;
    assign bypassQuery.rs2 = instInfo.rs2;
    bool_t ID_shouldHalt;
    assign ID_shouldHalt = bypassQuery.rs1ShouldHalt || bypassQuery.rs2ShouldHalt;
    // EX, MEM, WB bypass
    word_t ID_rs1Data, ID_rs2Data;
    assign ID_rs1Data = bypassQuery.rs1HasDep ? bypassQuery.rs1Data : ID_oldRs1Data;
    assign ID_rs2Data = bypassQuery.rs2HasDep ? bypassQuery.rs2Data : ID_oldRs2Data;

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
