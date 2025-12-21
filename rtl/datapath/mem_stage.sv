`timescale 1ns / 1ps

module mem_stage
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;
(
    input clk_t clk,
    input ex_mem_regs_t exMemRegs,
    input mem_control_t memControl,  // <- mostly rob hints
    output mem_wb_regs_t memWbRegs,
    output mem_hints_t memHints,
    cache_request_if.master cacheRequest,
    rob_store_queue_if.master storeQuery
`ifdef DATA_CACHE_DIVERGENCE_TEST
    , cache_request_if.master DEBUG_dataMemRequest
`endif
);

    word_t MEM_aluResult = exMemRegs.aluResult;
    inst_info_t MEM_instInfo = exMemRegs.instInfo;
    bool_t MEM_isLoad = MEM_instInfo.isLoad;
    addr_t MEM_virtAddr = MEM_aluResult;  // <- address calculation
    bool_t MEM_isStore = MEM_instInfo.isStore;
    word_t MEM_storeData = exMemRegs.stData;

    word_t MEM_loadData;

    mem_stlen_t MEM_stldDataLen;
    always_comb begin
        // if (MEM_instInfo.isStore || MEM_instInfo.isLoad) begin
        //     assert (MEM_instInfo.stldDataLen == DL_WORD)
        //     else $display("data length = %d", MEM_instInfo.stldDataLen);
        // end
        case (MEM_instInfo.stldDataLen)
            DL_BYTE: MEM_stldDataLen = MEM_STLEN_BYTE;
            DL_HALF: MEM_stldDataLen = MEM_STLEN_HALF;
            DL_WORD: MEM_stldDataLen = MEM_STLEN_WORD;
            default: MEM_stldDataLen = MEM_STLEN_INVALID;
        endcase
    end

    always_comb begin : CacheRequestSwitchLogic
        assert (!(MEM_readEnabled && MEM_writeEnabled));
        if (MEM_virtAddr == 'hcafebabe && MEM_writeEnabled && MEM_writeData == 'hbeafbabe) begin
            $display("Received stop signal, stopping...");
            $finish;
        end

        cacheRequest.request = FALSE;
        cacheRequest.isRead = FALSE;
        cacheRequest.addr = '0;
        cacheRequest.dataToCache = '0;
        cacheRequest.dataLen = MEM_STLEN_INVALID;

        memHints.ticket = exMemRegs.ticket;
        memHints.shouldHalt = FALSE;
        memHints.MEM_pipeIsLoad = FALSE;
        memHints.MEM_pipeLoadResult = '0;
        memHints.MEM_pipeLoadResultReady = FALSE;
        memHints.MEM_pipeIsStore = FALSE;
        memHints.MEM_pipeStoreData = '0;
        memHints.MEM_pipeStoreLen = MEM_STLEN_INVALID;
        memHints.MEM_robCommitStoreComplete = FALSE;

        if (memControl.ROB_oldestIsStore) begin // Highest priority to the oldest instruction
            // ROB commit STORE instruction: write to cache
            if (memControl.ROB_oldestStVirtAddrValid) begin
                cacheRequest.request = TRUE;
                cacheRequest.isRead = FALSE;
                // TODO: use PHYSICAL address
                cacheRequest.addr = memControl.ROB_oldestStVirtAddr.va;
                cacheRequest.dataToCache = memControl.ROB_oldestStData;
                cacheRequest.dataLen = memControl.ROB_oldestStDataLen;
                if (cacheRequest.ready) begin
                    memHints.MEM_robCommitStoreComplete = TRUE;
                end else begin
                    // wait until the cache write is complete
                    memHints.shouldHalt = TRUE;
                end
            end
        end else if (MEM_isLoad) begin
            memHints.MEM_pipeIsLoad = TRUE;
            // LOAD instruction: first bypass from ROB, if miss, then request cache
            robStoreQuery.virtAddr = {9'b0, MEM_virtAddr}; // TODO: set ASID in VA
            robStoreQuery.ticket = exMemRegs.tiket;
            if (robStoreQuery.hasEntry) begin
                // hit since STORE instruction is immediately written to the ROB
                if (robStoreQuery.sufficientLength) begin
                    MEM_pipeLoadData = robStoreQuery.data;
                    MEM_pipeLoadDataReady = TRUE;
                end else begin
                    // partial data update: wait until it is written to the cache
                    // then read from cache
                    // if written to cache, there should not be a ROB hit
                    memHints.shouldHalt = TRUE;
                end
            end else begin
                // ROB miss, request cache
                cacheRequest.request = TRUE;
                cacheRequest.isRead = TRUE;
                // TODO: use PHYSICAL address
                cacheRequest.addr = MEM_virtAddr;
                cacheRequest.dataLen = MEM_stldDataLen;
                memHints.MEM_pipeLoadResult = cacheRequest.dataFromCache;
                memHints.MEM_pipeLoadResultReady = cacheRequest.ready;
            end
        end else if (MEM_isStore) begin
            memHints.MEM_pipeIsStore = TRUE;
            // STORE instruction entry update: write to ROB
            memHints.MEM_pipeStoreData = MEM_storeData;
            memHints.MEM_pipeStoreLen = MEM_stldDataLen;
        end

        cacheRequest.request = MEM_readEnabled || MEM_writeEnabled;
        cacheRequest.isRead = MEM_readEnabled;
        cacheRequest.addr = MEM_addr;
        cacheRequest.dataToCache = MEM_writeData;
        cacheRequest.dataLen = MEM_readWriteDataLen;
        MEM_readData = cacheRequest.dataFromCache;
`ifdef DATA_CACHE_DIVERGENCE_TEST
        // request the data memory for divergence test
        DEBUG_dataMemRequest.request = cacheRequest.request;
        DEBUG_dataMemRequest.isRead = cacheRequest.isRead;
        DEBUG_dataMemRequest.addr = cacheRequest.addr;
        DEBUG_dataMemRequest.dataToCache = cacheRequest.dataToCache;
        DEBUG_dataMemRequest.dataLen = cacheRequest.dataLen;
`endif
    end

    always_comb begin : MemoryInstructionConsistencyCheck
        if (MEM_instInfo.isLoad || MEM_instInfo.isStore) begin
            assert (MEM_instInfo.stldDataLen != DL_INVALID);
            assert (MEM_readWriteDataLen != MEM_STLEN_INVALID);
        end
        if (cacheRequest.request && cacheRequest.isRead) begin
`ifdef DATA_CACHE_DIVERGENCE_TEST
            assert (DEBUG_dataMemRequest.dataLen != MEM_STLEN_INVALID);
`endif
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
