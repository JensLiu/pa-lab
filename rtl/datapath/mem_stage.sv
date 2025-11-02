`timescale 1ns / 1ps

module mem_stage
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;
(
`ifdef DATA_MEMORY_EXPOSE_INTERNALS
    output byte_t DEBUG_mem[DATA_MEM_SIZE],
`endif
    input clk_t clk,
    input ex_mem_regs_t exMemRegs,
    input mem_control_t memControl,  // <- empty
    output mem_wb_regs_t memWbRegs,
    output mem_hints_t memHints
);

    word_t MEM_aluResult = exMemRegs.aluResult;
    inst_info_t MEM_instInfo = exMemRegs.instInfo;
    word_t MEM_data;
    addr_t MEM_readAddr = MEM_aluResult;  // <- address calculation
    addr_t MEM_writeAddr = MEM_aluResult;
    bool_t MEM_writeEnabled = MEM_instInfo.isStore;
    word_t MEM_writeData = exMemRegs.stData;

    // FIXME: handle store types when is written to memory, should not extend zeros
    mem_stlen_t MEM_writeDataLen;
    always_comb begin
        if (MEM_instInfo.isStore) begin
            case (MEM_instInfo.stldDataLen)
                DL_BYTE: MEM_writeDataLen = MEM_STLEN_BYTE;
                DL_HALF: MEM_writeDataLen = MEM_STLEN_HALF;
                DL_WORD: MEM_writeDataLen = MEM_STLEN_WORD;
                default: MEM_writeDataLen = MEM_STLEN_INVALID;
            endcase
            $display("%h: @%h <- %h", exMemRegs.pc, MEM_writeAddr, MEM_writeData);
        end else begin
            MEM_writeDataLen = MEM_STLEN_INVALID;
        end
    end

    memory_data memData (
`ifdef DATA_MEMORY_EXPOSE_INTERNALS
        .DEBUG_mem(DEBUG_mem),
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
            $display("%h: @%h -> %h", exMemRegs.pc, MEM_readAddr, MEM_result);
        end else begin
            MEM_result = MEM_aluResult;
        end
    end

    always_comb begin
        // propagate
        memWbRegs.pc = exMemRegs.pc;
        memWbRegs.instInfo = MEM_instInfo;
        memWbRegs.memResult = MEM_result;
        memWbRegs.exceptions = exMemRegs.exceptions;
        // emit signal
        memHints.shouldHalt = FALSE;  // TODO: halt when requesting memory
        memHints.MEM_rd = MEM_instInfo.rd;
        memHints.MEM_isWriteback = MEM_instInfo.isWriteback;
        memHints.MEM_memResult = MEM_result;
    end

endmodule
;
