`timescale 1ns / 1ps

module mem_stage
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;
(
    input clk_t clk,
    input ex_mem_regs_t exMemRegs,
    input mem_control_t memControl,  // <- mostly rob hints
    output mem_hints_t memHints,
    cache_request_if.master cacheRequest,
    rob_store_query_if.master storeQuery
`ifdef DATA_CACHE_DIVERGENCE_TEST
    , cache_request_if.master DEBUG_dataMemRequest
`endif
);
    // TODO: stop load/store when WB stage commands halt
    //       - perhaps a state machine? since we cannot stop an ongoing cache request
    // Without a state machine, the following may happen: (while being asked to halt)
    //       - LOAD (pipeline): we issue the same load requests multiple times
    //          - nothing happens, we may load some unused data to the pipeline and ignore it
    //          - the first load may have a cache miss but the following load hits in cache
    //       - STORE (commit): we issue the same store requests multiple times
    //          - in single core system, it may be ok
    //          - we write as many entries to the store buffer as the number of cycles we are halted
    //          - while store buffer is draining, the first write may have cache miss,
    //            but the following writes hit in cache

    word_t MEM_aluResult = exMemRegs.aluResult;
    inst_info_t MEM_instInfo = exMemRegs.instInfo;
    bool_t MEM_isLoad = MEM_instInfo.isLoad;
    addr_t MEM_virtAddr = MEM_aluResult;  // <- address calculation
    bool_t MEM_isStore = MEM_instInfo.isStore;
    word_t MEM_storeData = exMemRegs.stData;

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

    always_comb begin : CacheRequestLogic
        assert (!(MEM_isLoad && MEM_isStore));
        if (MEM_virtAddr == 'hcafebabe && MEM_isStore && MEM_storeData == 'hbeafbabe) begin
            $display("[MEM]: @%0d Received stop signal, stopping...", DEBUG_tick);
            $finish;
        end

        cacheRequest.request = FALSE;
        cacheRequest.isRead = FALSE;
        cacheRequest.addr = '0;
        cacheRequest.dataToCache = '0;
        cacheRequest.dataLen = MEM_STLEN_INVALID;

        storeQuery.virtAddr = '0;
        storeQuery.ticket = ROB_TICKET_INVALID;

        if (memControl.ROB_commitIsStore) begin // Highest priority to the oldest instruction
            if (memControl.ROB_commitEntryValid) begin
                // ROB commit STORE instruction: write to cache
                if (memControl.ROB_commitStVirtAddrValid) begin
                    cacheRequest.request = TRUE;
                    cacheRequest.isRead = FALSE;
                    // TODO: use PHYSICAL address
                    cacheRequest.addr = memControl.ROB_commitStVirtAddr.va;
                    cacheRequest.dataToCache = memControl.ROB_commitStData;
                    cacheRequest.dataLen = memControl.ROB_commitStLen;
                end
            end
        end else if (MEM_isLoad) begin
            // LOAD instruction: first bypass from ROB, if miss, then request cache
            storeQuery.virtAddr = {9'b0, MEM_virtAddr}; // TODO: set ASID in VA
            storeQuery.ticket = exMemRegs.ticket;
            if (storeQuery.hasEntry) begin
                // hit since STORE instruction is immediately written to the ROB
                // No cache request needed
            end else begin
                // ROB miss, request cache
                cacheRequest.request = TRUE;
                cacheRequest.isRead = TRUE;
                // TODO: use PHYSICAL address
                cacheRequest.addr = MEM_virtAddr;
                cacheRequest.dataLen = MEM_stldDataLen;
            end
        end

`ifdef DATA_CACHE_DIVERGENCE_TEST
        // request the data memory for divergence test
        DEBUG_dataMemRequest.request = cacheRequest.request;
        DEBUG_dataMemRequest.isRead = cacheRequest.isRead;
        DEBUG_dataMemRequest.addr = cacheRequest.addr;
        DEBUG_dataMemRequest.dataToCache = cacheRequest.dataToCache;
        DEBUG_dataMemRequest.dataLen = cacheRequest.dataLen;
`endif
    end

    always_comb begin : MemHintsLogic
        memHints.ticket = exMemRegs.ticket;
        memHints.shouldHalt = FALSE;
        memHints.MEM_pipeIsLoad = FALSE;
        memHints.MEM_pipeLoadData = '0;
        memHints.MEM_pipeLoadDataReady = FALSE;
        memHints.MEM_isCommitStore = FALSE;
        memHints.MEM_commitStoreComplete = FALSE;

        if (memControl.ROB_commitIsStore) begin // Highest priority to the oldest instruction
            if (memControl.ROB_commitEntryValid) begin
                `MEM_STAGE_DEBUG_PRINT(
                    ("[MEM]: @%0d Committing STORE from ROB ticket %0d",
                                              DEBUG_tick,
                                      memControl.DEBUG_ROB_commitTicket));
                // paulse the pipeline, keep instructions
                memHints.shouldHalt = TRUE;
                // ROB commit STORE instruction: write to cache
                if (memControl.ROB_commitStVirtAddrValid) begin
                    memHints.MEM_isCommitStore = TRUE;
                    `MEM_STAGE_DEBUG_PRINT(
                        ("[MEM]: @%0d STORE to cache at PA %h from ROB ticket %0d: request=%0b, ready=%0b",
                                                  DEBUG_tick,
                                          memControl.ROB_commitStVirtAddr.va,
                                          memControl.DEBUG_ROB_commitTicket,
                                          cacheRequest.request,
                                          cacheRequest.ready));
                    if (cacheRequest.request && cacheRequest.ready) begin
                        `MEM_STAGE_DEBUG_PRINT(
                            ("[MEM]: @%0d STORE to cache at PA %h from ROB ticket %0d complete",
                                                      DEBUG_tick,
                                              memControl.ROB_commitStVirtAddr.va,
                                              memControl.DEBUG_ROB_commitTicket));
                        memHints.MEM_commitStoreComplete = TRUE;
                        memHints.shouldHalt = FALSE;
                    end
                end else begin
                    `MEM_STAGE_DEBUG_PRINT(("[MEM]: @%0d pending on commit from ROB ticket %0d",
                    DEBUG_tick, memControl.DEBUG_ROB_commitTicket));
                end
            end
        end else if (MEM_isLoad) begin
            memHints.MEM_pipeIsLoad = TRUE;
            // LOAD instruction: first bypass from ROB, if miss, then request cache
            if (storeQuery.hasEntry) begin
                // hit since STORE instruction is immediately written to the ROB
                if (storeQuery.sufficientLength) begin
                    `MEM_STAGE_DEBUG_PRINT(
                        ("[MEM]: @%0d LOAD from ROB ticket %0d hit, returning data %h",
                                                  DEBUG_tick,
                                          exMemRegs.ticket,
                                          storeQuery.data));
                    memHints.MEM_pipeLoadData = storeQuery.data;
                    memHints.MEM_pipeLoadDataReady = TRUE;
                end else begin
                    `MEM_STAGE_DEBUG_PRINT(
                        ("[MEM]: @%0d LOAD from ROB ticket %0d: hit, but insufficient length",
                                                  DEBUG_tick,
                                          exMemRegs.ticket));
                    // partial data update: wait until it is written to the cache
                    // then read from cache
                    // if written to cache, there should not be a ROB hit, hence we will
                    // move to the `else` branch on the next rising edge of the clock
                    memHints.shouldHalt = TRUE;
                end
            end else begin
                `MEM_STAGE_DEBUG_PRINT(
                    ("[MEM]: @%0d LOAD from ROB ticket %0d: miss, requesting cache at PA %h (ready=%0b, returning data %h)",
                                              DEBUG_tick,
                                      exMemRegs.ticket,
                                      MEM_virtAddr,
                                      cacheRequest.ready,
                                      cacheRequest.dataFromCache));
                // ROB miss, request cache
                // halt until cache request finishes
                memHints.shouldHalt = !cacheRequest.ready;
                memHints.MEM_pipeLoadData = cacheRequest.dataFromCache;
                memHints.MEM_pipeLoadDataReady = cacheRequest.ready;
            end
        end

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
            assert (MEM_stldDataLen != MEM_STLEN_INVALID);
        end
        if (cacheRequest.request && cacheRequest.isRead) begin
`ifdef DATA_CACHE_DIVERGENCE_TEST
            assert (DEBUG_dataMemRequest.dataLen != MEM_STLEN_INVALID);
`endif
            assert (cacheRequest.dataLen != MEM_STLEN_INVALID);
        end
    end

    logic [31:0] DEBUG_tick;
    always_ff @(posedge clk) begin
        DEBUG_tick <= DEBUG_tick + 1;
    end

    always_ff @( posedge clk ) begin
        `MEM_STAGE_DEBUG_PRINT(("[MEM]: @%0d: ticket=%0d, isLoad=%0b, isStore=%0b, virtAddr=%h, storeData=%h",
                                          DEBUG_tick,
                                  exMemRegs.ticket,
                                  MEM_instInfo.isLoad,
                                  MEM_instInfo.isStore,
                                  MEM_virtAddr,
                                  MEM_storeData));
    end

`ifdef DATA_CACHE_DIVERGENCE_TEST
    always_ff @(posedge clk) begin : DEBUG_DivergenceTest
        if (MEM_instInfo.isLoad && cacheRequest.ready) begin
            if (cacheRequest.dataFromCache != DEBUG_dataMemRequest.dataFromCache) begin
                $display("@%d: Divergent: MEM @PA%h: cache %h != dataMem %h", DEBUG_tick, cacheRequest.addr,
                         cacheRequest.dataFromCache, DEBUG_dataMemRequest.dataFromCache);
            end
            assert (DEBUG_dataMemRequest.ready);
            assert (cacheRequest.dataFromCache == DEBUG_dataMemRequest.dataFromCache);
        end
    end
`endif

endmodule
