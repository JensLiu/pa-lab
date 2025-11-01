`include "rtl_common.svh"

module datapath
    import pkg_global_defs::*;
    import pkg_riscv_instructions::*;
(
`ifdef DATAPATH_EXPOSE_INTERNALS
    output reg_t DEBUG_pc,
    output instruction_t DEBUG_inst,
    output reg_t DEBUG_regs[32],
    output reg_nr_t DEBUG_WB_rdIdx,
    output word_t DEBUG_WB_data,
    output bool_t DEBUG_WB_isWriteback,
`ifdef INSTRUCTION_MEMORY_EXPOSE_INTERNALS
    output byte_t DEBUG_inst_mem[INST_MEM_SIZE],
`endif
`ifdef DATA_MEMORY_EXPOSE_INTERNALS
    output byte_t DEBUG_data_mem[DATA_MEM_SIZE],
`endif
`endif
    input clk_t clk
);

    // INSTRUCTION FETCH begin -----------------------------------
    reg_t  IF_pcQ;
    reg_t  EX_pcBr;
    bool_t EX_branchTaken;
`ifdef DATAPATH_EXPOSE_INTERNALS
    assign DEBUG_pc = IF_pcQ;
    assign DEBUG_inst = IF_inst;
    assign DEBUG_WB_rdIdx = WB_rdIdx;
    assign DEBUG_WB_data = WB_data;
    assign DEBUG_WB_isWriteback = WB_isWriteback;
`endif

`ifdef SINGLE_CYCLE
    reg_t IF_pcNext;
    assign IF_pcNext = IF_pcQ + 4;
    always_ff @(posedge clk) begin
        if (EX_branchTaken) begin
            IF_pcQ <= EX_pcBr;
        end else begin
            IF_pcQ <= IF_pcNext;
        end
    end
`endif

    instruction_t IF_inst;
    memory_inst memInst (
`ifdef INSTRUCTION_MEMORY_EXPOSE_INTERNALS
        .DEBUG_mem(DEBUG_inst_mem),
`endif
        .clk(clk),
        .addr(IF_pcQ),
        .inst(IF_inst)
    );
    // INSTRUCTION FETCH end -------------------------------------

    // INSTRUCTION DECODING begin --------------------------------
    reg_t ID_pc = IF_pcQ;
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
    reg_t EX_pc = ID_pc;
    inst_info_t EX_instInfo = ID_instInfo;

    // ALU
    word_t EX_aluA;
    word_t EX_aluB;
    always_comb begin
        if (EX_instInfo.branchType == BR_INVALID) begin
            // normal operations
            EX_aluA = ID_rs1Data;
            EX_aluB = EX_instInfo.aluUseImmAsRs2 ? EX_instInfo.imm : ID_rs2Data;
        end else if (EX_instInfo.branchType != BR_UNCOND) begin
            // normal branch
            EX_aluA = EX_pc;  // PC
            assert (EX_instInfo.aluUseImmAsRs2);
            assert (EX_aluOp == ALU_ADD);
            EX_aluB = EX_instInfo.imm;  // OFFSET
        end else begin
            // jump
            EX_aluA = EX_pc;
            assert (!EX_instInfo.aluUseImmAsRs2);
            assert (EX_aluOp == ALU_ADD);
            EX_aluB = 32'h4;
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
    imm_arith_t EX_cmpA = ID_rs1Data;
    imm_arith_t EX_cmpB = ID_rs2Data;
    bool_t EX_cmpIsSigned = EX_instInfo.cmpIsSigned;
    comparator cmp (
        .A(EX_cmpA),
        .B(EX_cmpB),
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

    always_comb begin
        if (EX_instInfo.branchType == BR_UNCOND) begin
            EX_pcBr = EX_instInfo.imm;
            // TODO: Store PC_NEXT to register rd for `jal`
        end else begin
            EX_pcBr = EX_aluResult;  // PC + offset
        end
    end

    // EXECUTION end ---------------------------------------

    // MEMORY begin ----------------------------------------
    word_t MEM_aluResult = EX_aluResult;
    inst_info_t MEM_instInfo = EX_instInfo;
    word_t MEM_data;
    addr_t MEM_readAddr = MEM_aluResult;  // <- address calculation
    addr_t MEM_writeAddr = MEM_aluResult;  // pipelined?
    bool_t MEM_writeEnabled = MEM_instInfo.isStore;
    word_t MEM_writeData = ID_rs2Data;
    mem_stlen_t MEM_writeDataLen;
    // FIXME: handle store types when is written to memory, should not extend zeros
    always_comb begin
        if (MEM_instInfo.isStore) begin
            case (MEM_instInfo.stldDataLen)
                DL_BYTE: MEM_writeDataLen = MEM_STLEN_BYTE;
                DL_HALF: MEM_writeDataLen = MEM_STLEN_HALF;
                DL_WORD: MEM_writeDataLen = MEM_STLEN_WORD;
                default: MEM_writeDataLen = MEM_STLEN_INVALID;
            endcase
        end else begin
            MEM_writeDataLen = MEM_STLEN_INVALID;
        end
    end

    memory_data memData (
`ifdef DATA_MEMORY_EXPOSE_INTERNALS
        .DEBUG_mem(DEBUG_data_mem),
`endif
        .clk(clk),
        .readAddr(MEM_readAddr),
        .writeAddr(MEM_writeAddr),
        .writeData(MEM_writeData),
        .writeDataLen(MEM_writeDataLen),
        .writeEnable(MEM_writeEnabled),
        .readData(MEM_data)
    );

    // word_t MEM_result = MEM_instInfo.isLoad ? MEM_data : MEM_aluResult;
    word_t MEM_result;
    always_comb begin
        if (MEM_instInfo.isLoad) begin
            case (MEM_instInfo.stldDataLen)
                DL_BYTE: MEM_result = {{24{1'b0}}, MEM_data[7:0]};
                DL_HALF: MEM_result = {{16{1'b0}}, MEM_data[15:0]};
                DL_WORD: MEM_result = MEM_data[31:0];
                default: assert (FALSE);
            endcase
        end else begin
            MEM_result = MEM_aluResult;
        end
    end

    // MEMORY end ------------------------------------------

    // WRITEBACK begin -------------------------------------
    inst_info_t WB_inst = EX_instInfo;
    assign WB_rdIdx = EX_instInfo.rd;
    assign WB_isWriteback = EX_instInfo.isWriteback;
    assign WB_data = MEM_result;
    // WRITEBACK end   -------------------------------------

endmodule
