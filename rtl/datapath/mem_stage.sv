`timescale 1ns / 1ps

module mem_stage
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;
(
    input clk_t clk,
    input ex_mem_regs_t exMemRegs,
    input mem_control_t memControl,  // <- empty
    output mem_wb_regs_t memWbRegs,
    output mem_hints_t memHints,
    cache_request_if.master cacheRequest
`ifdef DATA_CACHE_DIVERGENCE_TEST
    , cache_request_if.master DEBUG_dataMemRequest
`endif
);

    word_t MEM_aluResult = exMemRegs.aluResult;
    inst_info_t MEM_instInfo = exMemRegs.instInfo;
    word_t MEM_readData;
    bool_t MEM_readEnabled = MEM_instInfo.isLoad;
    addr_t MEM_addr = MEM_aluResult;  // <- address calculation
    bool_t MEM_writeEnabled = MEM_instInfo.isStore;
    word_t MEM_writeData = exMemRegs.stData;

    mem_stlen_t MEM_readWriteDataLen;
    always_comb begin
        // if (MEM_instInfo.isStore || MEM_instInfo.isLoad) begin
        //     assert (MEM_instInfo.stldDataLen == DL_WORD)
        //     else $display("data length = %d", MEM_instInfo.stldDataLen);
        // end
        case (MEM_instInfo.stldDataLen)
            DL_BYTE: MEM_readWriteDataLen = MEM_STLEN_BYTE;
            DL_HALF: MEM_readWriteDataLen = MEM_STLEN_HALF;
            DL_WORD: MEM_readWriteDataLen = MEM_STLEN_WORD;
            default: MEM_readWriteDataLen = MEM_STLEN_INVALID;
        endcase
    end

    always_comb begin
        assert (!(MEM_readEnabled && MEM_writeEnabled));
        cacheRequest.request = MEM_readEnabled || MEM_writeEnabled;
        cacheRequest.isRead = MEM_readEnabled;
        cacheRequest.addr = MEM_addr;
        cacheRequest.dataToCache = MEM_writeData;
        cacheRequest.dataLen = MEM_readWriteDataLen;
        MEM_readData = cacheRequest.dataFromCache;
        // request the data memory for divergence test
        DEBUG_dataMemRequest.request = cacheRequest.request;
        DEBUG_dataMemRequest.isRead = cacheRequest.isRead;
        DEBUG_dataMemRequest.addr = cacheRequest.addr;
        DEBUG_dataMemRequest.dataToCache = cacheRequest.dataToCache;
        DEBUG_dataMemRequest.dataLen = cacheRequest.dataLen;
    end

    always_comb begin : MemoryInstructionConsistencyCheck
        if (MEM_instInfo.isLoad || MEM_instInfo.isStore) begin
            assert (MEM_instInfo.stldDataLen != DL_INVALID);
            assert (MEM_readWriteDataLen != MEM_STLEN_INVALID);
        end
        if (cacheRequest.request && cacheRequest.isRead) begin
            assert (DEBUG_dataMemRequest.dataLen != MEM_STLEN_INVALID);
            assert (cacheRequest.dataLen != MEM_STLEN_INVALID);
        end
    end

    word_t MEM_result;
    always_comb begin
        if (MEM_instInfo.isLoad && cacheRequest.ready) begin
            MEM_result = MEM_readData;
            // endcase
            // if (cacheRequest.dataFromCache != DEBGU_dataMemRequest.dataFromCache) begin
            //     $display("@%d: Divergent: MEM @%h: cache %h != dataMem %h", DEBUG_tick, MEM_addr,
            //              cacheRequest.dataFromCache, DEBGU_dataMemRequest.dataFromCache);
            // end
            // assert (DEBGU_dataMemRequest.ready);
            // assert (cacheRequest.dataFromCache == DEBGU_dataMemRequest.dataFromCache);
            // $display("%h: @%h -> %h", exMemRegs.pc, MEM_addr, MEM_result);
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
        memHints.shouldHalt = cacheRequest.request && !cacheRequest.ready;
        memHints.MEM_rd = MEM_instInfo.rd;
        memHints.MEM_isWriteback = MEM_instInfo.isWriteback;
        memHints.MEM_memResult = MEM_result;
    end

    logic [31:0] DEBUG_tick;
    always_ff @(posedge clk) begin
        DEBUG_tick <= DEBUG_tick + 1;
    end

`ifdef DATA_CACHE_DIVERGENCE_TEST
    always_ff @(posedge clk) begin : DEBUG_DivergenceTest
        if (MEM_instInfo.isLoad && cacheRequest.ready) begin
            if (cacheRequest.dataFromCache != DEBUG_dataMemRequest.dataFromCache) begin
                $display("@%d: Divergent: MEM @%h: cache %h != dataMem %h", DEBUG_tick, MEM_addr,
                         cacheRequest.dataFromCache, DEBUG_dataMemRequest.dataFromCache);
            end
            assert (DEBUG_dataMemRequest.ready);
            assert (cacheRequest.dataFromCache == DEBUG_dataMemRequest.dataFromCache);
        end
    end
`endif

endmodule
