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

    bool_t IF_instValid;
    assign IF_instValid = ifIdRegs.instValid;

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
    bool_t dependencyShouldHalt;
    assign dependencyShouldHalt = rs1ShouldHalt || rs2ShouldHalt;
    word_t ID_rs1Data, ID_rs2Data;
    always_comb begin : BypassQueryLogic
        regQuery.rs1 = instInfo.rs1;
        regQuery.rs2 = instInfo.rs2;
        rs1ShouldHalt = regQuery.rs1HasEntry && !regQuery.rs1DataValid;
        rs2ShouldHalt = regQuery.rs2HasEntry && !regQuery.rs2DataValid;
        ID_rs1Data = regQuery.rs1HasEntry ? regQuery.rs1Data : ID_oldRs1Data;
        ID_rs2Data = regQuery.rs2HasEntry ? regQuery.rs2Data : ID_oldRs2Data;
        `ID_STAGE_DEBUG_PRINT(
            ("[ID]: @%0d: ticket=%0d, inst=%h", DEBUG_tick, ticket, instInfo.DEBUG_instBinary));
        `ID_STAGE_DEBUG_PRINT(
            ("[ID]: @%0d Querying ROB for rs1=%0d, rs2=%0d",
                              DEBUG_tick,
                              instInfo.rs1,
                              instInfo.rs2));
        `ID_STAGE_DEBUG_PRINT(
            ("[ID]: @%0d rs1= %0d, rs1HasEntry=%0b, rs1DataValid=%0b, rs1Data(Queried)=%h, rs1Data(Selected)=%h",
                              DEBUG_tick,
                              instInfo.rs1,
                              regQuery.rs1HasEntry,
                              regQuery.rs1DataValid,
                              regQuery.rs1Data,
                              ID_rs1Data));
        `ID_STAGE_DEBUG_PRINT(
            ("[ID]: @%0d rs2= %0d, rs2HasEntry=%0b, rs2DataValid=%0b, rs2Data(Queried)=%h, rs2Data(Selected)=%h",
                              DEBUG_tick,
                              instInfo.rs2,
                              regQuery.rs2HasEntry,
                              regQuery.rs2DataValid,
                              regQuery.rs2Data,
                              ID_rs2Data));
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
    bool_t _ticketShouldRequest;
    assign _ticketShouldRequest = !idControl.halt && IF_instValid && !dependencyShouldHalt;
    bool_t ticketShouldHalt;
    always_comb begin : RobTicketRequestLogic
        `ID_STAGE_DEBUG_PRINT(
            ("[ID]: @%0d Preparing ROB ticket request: IF_instValid=%0b, dependencyShouldHalt=%0b",
                          DEBUG_tick,
                          IF_instValid,
                          dependencyShouldHalt));
        ticketRequest.request = _ticketShouldRequest;
        ticketRequest.isStore = instInfo.isStore;
        ticketRequest.isWriteback = instInfo.isWriteback;
        ticketRequest.isBranch = instInfo.branchType != BR_INVALID;
        ticketRequest.stLen = ID_stldDataLen;
        ticketRequest.stData = ID_rs2Data;
        ticketRequest.rd = instInfo.rd;
        ticketRequest.pc = ifIdRegs.pc;
        ticketRequest.DEBUG_instInfo = instInfo;
        ticket = ticketRequest.ticket;
        ticketShouldHalt = _ticketShouldRequest && !ticketRequest.ready;
        if (_ticketShouldRequest) begin
            `ID_STAGE_DEBUG_PRINT(
                ("[ID]: @%0d Requested ROB ticket for instruction at PC %h: ticket=%0d, ready=%0b",
                              DEBUG_tick,
                              ifIdRegs.pc,
                              ticket,
                              ticketRequest.ready));
        end
    end

    // Only halt if the fetch instruction is valid and there is a dependency stall
    bool_t ID_shouldHalt;
    assign ID_shouldHalt = IF_instValid && (dependencyShouldHalt || ticketShouldHalt);
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
            `ID_STAGE_DEBUG_PRINT(
                ("[ID]: @%0d Deligating IMUL instruction at PC %h to IMUL pipeline with ticket %0d",
                                  DEBUG_tick,
                                  ifIdRegs.pc,
                                  ticket));
            idImulRegs.ticket = ticket;
            idImulRegs.A = ID_rs1Data;
            idImulRegs.B = ID_rs2Data;
        end else begin
            // deligate to the EX-MEM pipeline
            `ID_STAGE_DEBUG_PRINT(
                ("[ID]: @%0d Deligating instruction at PC %h to EX stage with ticket %0d",
                                  DEBUG_tick,
                                  ifIdRegs.pc,
                                  ticket));
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
        `ID_STAGE_DEBUG_PRINT(
            ("[ID]: @%0d ID_shouldHalt=%0b (IF_instValid=%0b, dependencyShouldHalt=%0b, ticketShouldHalt=%0b)",
                              DEBUG_tick,
                              ID_shouldHalt,
                              IF_instValid,
                              dependencyShouldHalt,
                              ticketShouldHalt));
    end

    word_t DEBUG_tick;
    always_ff @(posedge clk) begin
        DEBUG_tick <= DEBUG_tick + 1;
    end

endmodule
