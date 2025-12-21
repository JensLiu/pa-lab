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
    output id_imul_regs_t idImulRegs,
    output id_hints_t idHints,
    rob_reg_query_if.master regQuery,
    rob_ticket_request_if.master ticketRequest
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

    // bypass network queries
    bool_t rs1ShouldHalt, rs2ShouldHalt;
    word_t ID_rs1Data, ID_rs2Data;
    always_comb begin : BypassQueryLogic
        regQuery.rs1 = instInfo.rs1;
        regQuery.rs2 = instInfo.rs2;
        rs1ShouldHalt = regQuery.rs1HasEntry && !regQuery.rs1DataValid;
        rs2ShouldHalt = regQuery.rs2HasEntry && !regQuery.rs2DataValid;
        ID_rs1Data = regQuery.rs1HasEntry ? regQuery.rs1Data : ID_oldRs1Data;
        ID_rs2Data = regQuery.rs2HasEntry ? regQuery.rs2Data : ID_oldRs2Data;
    end

    mem_stlen_t ID_stldDataLen;
    always_comb begin
        // if (MEM_instInfo.isStore || MEM_instInfo.isLoad) begin
        //     assert (MEM_instInfo.stldDataLen == DL_WORD)
        //     else $display("data length = %d", MEM_instInfo.stldDataLen);
        // end
        case (instInfo.stldDataLen)
            DL_BYTE: ID_stldDataLen = MEM_STLEN_BYTE;
            DL_HALF: ID_stldDataLen = MEM_STLEN_HALF;
            DL_WORD: ID_stldDataLen = MEM_STLEN_WORD;
            default: ID_stldDataLen = MEM_STLEN_INVALID;
        endcase
    end

    word_t ticket;
    bool_t ticketShouldHalt;
    always_comb begin : RobTicketRequestLogic
        ticketRequest.request = !ID_shouldHalt;
        ticketRequest.isStore = instInfo.isStore;
        ticketRequest.stLen = ID_stldDataLen;
        ticketRequest.stData = ID_rs2Data;
        ticketRequest.isWriteback = instInfo.isWriteback;
        ticketRequest.rd = instInfo.rd;
        ticketRequest.pc = ifIdRegs.pc;
        ticketRequest.DEBUG_instInfo = instInfo;
        ticket = ticketRequest.ticket;
        ticketShouldHalt = !ticketRequest.ready;
    end


    bool_t ID_shouldHalt = rs1ShouldHalt || rs2ShouldHalt || ticketShouldHalt;
    always_comb begin
        // default values
        idImulRegs.ticket = ROB_TICKET_INVALID;
        idImulRegs.A = IMM_32_WHATEVER;
        idImulRegs.B = IMM_32_WHATEVER;
        idExRegs.ticket = ROB_TICKET_INVALID;
        idExRegs.pc = '0;
        idExRegs.instInfo = inst_info_make_nop();
`ifdef DEBUG_INST_INFO_EXTENSION
        idExRegs.instInfo.DEBUG_instID = ifIdRegs.DEBUG_instID;
`endif
        idExRegs.rs1Data = IMM_32_WHATEVER;
        idExRegs.rs2Data = IMM_32_WHATEVER;
        idExRegs.exceptions = '0;

        // propagate pipeline
        if (instInfo.isImul) begin
            // deligate to the multiplication pipeline
            idImulRegs.ticket = ticket;
            idImulRegs.A = ID_rs1Data;
            idImulRegs.B = ID_rs2Data;
        end else begin
            // deligate to the EX-MEM pipeline
            idExRegs.ticket = ticket;
            idExRegs.pc = ifIdRegs.pc;
            idExRegs.instInfo = instInfo;
`ifdef DEBUG_INST_INFO_EXTENSION
            idExRegs.instInfo.DEBUG_instID = ifIdRegs.DEBUG_instID;
`endif
            idExRegs.rs1Data = ID_rs1Data;
            idExRegs.rs2Data = ID_rs2Data;
            idExRegs.exceptions = ifIdRegs.exceptions;

        end

        // emit signal
        idHints.shouldHalt = ID_shouldHalt;
    end

endmodule
