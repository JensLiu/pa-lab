`define SINGLE_CYCLE

`define DATAPATH_EXPOSE_INTERNALS

module datapath
    import pkg_global_defs::*;
    import pkg_riscv_instructions::*;
(
`ifdef DATAPATH_EXPOSE_INTERNALS
    output reg_t DEBUG_pc,
    output instruction_t DEBUG_inst,
    output reg_t DEBUG_regs[0:31],
`endif
    input clk_t clk
);

    // INSTRUCTION FETCH begin -----------------------------------
    reg_t  IF_pc;
    reg_t  EX_pcBr;
    bool_t EX_branchTaken;

`ifdef SINGLE_CYCLE
    always_ff @(posedge clk) begin
        if (EX_branchTaken) begin
            IF_pc <= EX_pcBr;
        end else begin
            IF_pc <= IF_pc + 4;
        end
    end
`endif

    instruction_t IF_inst;
    memory_inst memInst (
        clk,
        IF_pc,
        IF_inst
    );
    // INSTRUCTION FETCH end -------------------------------------

    // INSTRUCTION DECODING begin --------------------------------
    inst_info_t ID_instInfo;
    decoder decoder (
        .inst(IF_inst),
        .info(ID_instInfo)
    );

    reg_nr_t WB_rdIdx;
    word_t   WB_data;
    bool_t   WB_isWriteback;
    word_t ID_rs1Data, ID_rs2Data;

    register_file rf (
`ifdef DATAPATH_EXPOSE_INTERNALS
        .debug_regs(DEBUG_regs),
        // .debug_is_writing(0),
`endif
        .clk(clk),
        .read_reg1(ID_instInfo.rs1),
        .read_reg2(ID_instInfo.rs2),
        .write_reg(WB_rdIdx),
        .write_data(WB_data),
        .write_enable(WB_isWriteback),
        .read_data1(ID_rs1Data),
        .read_data2(ID_rs2Data)
    );
    // INSTRUCTION DECODING end -------------------------

    // EXECUTION begin -------------------------------------
    inst_info_t EX_instInfo = ID_instInfo;

    // ALU
    word_t EX_aluA = ID_rs1Data;
    word_t EX_aluB = (EX_instInfo.aluUseImm ? EX_instInfo.imm : ID_rs2Data);
    alu_op_t EX_aluOp = EX_instInfo.aluOp;
    word_t EX_aluResult;
    alu alu (
        .A(EX_aluA),
        .B(EX_aluB),
        .aluOp(EX_aluOp),
        .Y(EX_aluResult)
    );

    // CMP
    cmp_result_t EX_cmpResult;
    imm_arith_t EX_cmpA = ID_rs1Data;
    imm_arith_t EX_cmpB = ID_rs2Data;
    bool_t EX_cmpIsSigned = EX_instInfo.cmpIsSigned;
    comparator cmp (
        .A(EX_cmpA),
        .B(EX_aluB),
        .isSigned(EX_cmpIsSigned),
        .res(EX_cmpResult)
    );

    // Branch
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
    // EXECUTION end ---------------------------------------

    // MEMORY begin ----------------------------------------
    word_t MEM_aluResult = EX_aluResult;
    inst_info_t MEM_instInfo = EX_instInfo;
    word_t MEM_data;
    addr_t MEM_readAddr = EX_aluResult;  // <- address calculation
    addr_t MEM_writeAddr = EX_aluResult;  // pipelined?
    word_t MEM_writeData = ID_rs2Data;  // pipelined?
    bool_t MEM_writeEnabled = MEM_instInfo.isStore;

    memory_data memData (
        clk,
        MEM_readAddr,
        MEM_writeAddr,
        MEM_writeData,
        MEM_writeEnabled,
        MEM_data
    );

    word_t MEM_result = MEM_instInfo.isLoad ? MEM_data : MEM_aluResult;
    // MEMORY end ------------------------------------------

    // WRITEBACK begin -------------------------------------
    inst_info_t WB_inst = EX_instInfo;
    assign WB_rdIdx = EX_instInfo.rd;
    assign WB_isWriteback = EX_instInfo.isWriteback;
    assign WB_data = MEM_result;
    // WRITEBACK end   -------------------------------------

endmodule
