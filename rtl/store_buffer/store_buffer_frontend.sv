`include "rtl_common.svh"

module store_buffer_frontend
    import pkg_global_defs::*;
(
    input logic clk,
    cache_request_if.slave cpuRequest,
    cache_request_if.master deligatedCpuRequest,
    cache_hit_query_if.master cacheHitQuery
);
    // store buffer combinational read
    addr_t sbReadAddr;
    mem_stlen_t sbReadDataLen;
    word_t sbReadData;
    bool_t sbReadHit;
    addr_range_coverage_t sbReadHitRange;
    // store buffer sequential write
    bool_t sbCanWrite;
    bool_t sbWriteRequest;
    addr_t sbWriteAddr;
    word_t sbWriteData;
    mem_stlen_t sbWriteDataLen;

    // store buffer interrupt lane
    // NOTE: Flipflop introducecd to fix
    //       ```
    //          sbInterrupt = TRUE;
    //          if (sbInterrupted) begin
    //              somehow deligatedCpuRequest <-> cpuRequest
    //          end
    //       ```
    //       If we use combinational logic for sbInterrupted, we will get a loop
    //       (1) sbInterrupted -> sbCacheWriteOnlyRequest.ready -> deligatedCpuRequest
    //       (2) at the same clock cycle, if sbInterrupted, we change the deligatedCpuRequest
    //      Hence the loop deligatedCpuRequest -> sbInterupted -> sbCacheOnlyRequest -> deligatedCpuRequest
    // FIXME: We lost the instant interrupt response from the store buffer
    bool_t sbInterruptQ, sbInterruptedP;
    bool_t sbInterruptedQ;

    cache_writeonly_request_if sbCacheWriteOnlyRequest ();

    store_buffer storeBuffer (
        .clk(clk),
        .readAddr(sbReadAddr),
        .readDataLen(sbReadDataLen),
        .readData(sbReadData),
        .readHit(sbReadHit),
        .readHitRange(sbReadHitRange),
        .sbCanWrite(sbCanWrite),
        .writeRequest(sbWriteRequest),
        .writeAddr(sbWriteAddr),
        .writeData(sbWriteData),
        .writeDataLen(sbWriteDataLen),
        .interrupt(sbInterruptQ),
        .interrupted(sbInterruptedP),
        .cacheRequest(sbCacheWriteOnlyRequest.master)
    );

    typedef enum logic [1:0] {
        IDLE,
        INTERRUPTING,
        INTERRUPTED
    } sb_frontend_state_t;

    sb_frontend_state_t currentState, nextState;

    // we constantly query the store buffer and the cache for hit
    bool_t sbIsHit, cacheIsHit;
    word_t sbHitData, cacheHitData;
    always_comb begin : StoreBufferHitLogic
        sbReadAddr = cpuRequest.addr;
        sbReadDataLen = cpuRequest.dataLen;
        sbHitData = sbReadData;
        sbIsHit = sbReadHit;
    end
    always_comb begin : CacheHitLogic
        cacheHitQuery.addr    = cpuRequest.addr;
        cacheHitQuery.dataLen = cpuRequest.dataLen;
        cacheIsHit            = cacheHitQuery.isHit;
        cacheHitData          = cacheHitQuery.dataFromCache;
    end

    always_ff @(posedge clk) begin : InterruptLogic
        sbInterruptedQ <= sbInterruptedP;
        sbInterruptQ   <= FALSE;
        if (currentState == INTERRUPTING || currentState == INTERRUPTED) begin
            sbInterruptQ <= TRUE;
        end
    end

    always_ff @(posedge clk) begin : StateUpdate
        currentState <= nextState;
    end

    always_comb begin : NextStateLogic
        nextState = currentState;
        case (currentState)
            IDLE: begin
                if (cpuRequest.request && cpuRequest.isRead) begin
                    if (!sbIsHit && !cacheIsHit) begin
                        // TODO: we are wasting one cycle here, update the
                        //       state machine to allow immediate interrupt
                        //       (a more complicated interrupt logic)
                        nextState = INTERRUPTING;
                    end
                end
            end
            INTERRUPTING: begin
                if (sbInterruptedQ) begin
                    nextState = INTERRUPTED;
                end
            end
            INTERRUPTED: begin
                if (!cpuRequest.request) begin
                    nextState = IDLE;
                end
            end
            default: `ASSERT(FALSE);
        endcase
    end

    always_comb begin
        // default response: not ready
        cpuRequest.ready = FALSE;
        cpuRequest.failed = FALSE;
        cpuRequest.dataFromCache = '0;

        // default cache request: SB draining
        sbCacheWriteOnlyRequest.ready = deligatedCpuRequest.ready;
        deligatedCpuRequest.request = sbCacheWriteOnlyRequest.master.request;
        deligatedCpuRequest.isRead = FALSE;
        deligatedCpuRequest.invalidateAll = FALSE;
        deligatedCpuRequest.addr = sbCacheWriteOnlyRequest.addr;
        deligatedCpuRequest.dataToCache = sbCacheWriteOnlyRequest.dataToCache;
        deligatedCpuRequest.dataLen = sbCacheWriteOnlyRequest.dataLen;

        // default SB write request: none
        sbWriteRequest = FALSE;
        sbWriteAddr = '0;
        sbWriteData = '0;
        sbWriteDataLen = MEM_STLEN_INVALID;

        if (cpuRequest.request) begin
            if (currentState == IDLE) begin
                if (cpuRequest.isRead) begin : ReadRequestDeligate
                    // NOTE: data flushed to cache will ONLY be unavailable in the NEXT CYCLE
                    //       so it's safe to return immediately since we expect the requester to
                    //       immediately record its value in the current cycle

                    // this is preemptive, meaning that when we are requesting cache, while waiting for cache
                    // to response, if there is another write request to the store buffer that have the newest value
                    // `sbReadHit` will evaluate true and return the new value immediately
                    // NOTE: we execute stores and load sequentially, so the above-metioned senario will NOT happen
                    //       since while we are surving load, the next store instruction has not executed and the previous
                    //       store instruction already updated the store buffer

                    // (1) Query for store buffer hit, this is combinational
                    if (sbIsHit) begin
                        // Store buffer hit, return immediately
                        `SB_FRONTEND_DEBUG_PRINT(
                            ("[SB FRONT]: @%0d: SB Hit Addr=%h Data=%h Len=%0d",
                            DEBUG_tick, cpuRequest.addr, sbHitData, cpuRequest.dataLen));
                        `SB_FRONTEND_DEBUG_PRINT((
                            "[SB FRONT]: @%0d: SB Hit Data Range=%0d",
                            DEBUG_tick, sbReadHitRange));
                        case (cpuRequest.dataLen)
                            MEM_STLEN_BYTE: cpuRequest.dataFromCache = {24'h0, sbHitData[7:0]};
                            MEM_STLEN_HALF: cpuRequest.dataFromCache = {16'h0, sbHitData[15:0]};
                            MEM_STLEN_WORD: cpuRequest.dataFromCache = sbHitData[31:0];
                            MEM_STLEN_INVALID: cpuRequest.dataFromCache = '0;
                            default: cpuRequest.dataFromCache = '0;
                        endcase
                        // partial coverage, we do not bypass, wait until SB drains this entry
                        // i.e. no sbIsHit in the next cycle
                        cpuRequest.ready = sbReadHitRange == ADDR_FULLY_IN_RANGE;
                    end else begin
                        // Store buffer miss, fallback to cache
                        // (2) Query for cache hit, this is all combinational (can be done in a single clock)
                        //     We don't want to interrupt SB draining everytime we want to query the cache,
                        //     if there's a cache hit, we immediately return the hit result
                        if (cacheIsHit) begin
                            // NOTE: In this case, we eliminate the possibility of reading the "dirty data"
                            //       within a write transaction since
                            //      (a) If the store buffer is writing to the cache and the transaction has not
                            //          yet finished, there is the latest data in the store buffer, and we return
                            //          the data inside the store buffer (we will not read the cache)
                            //      (b) If the store buffer finished writing to the cache and has deleted the record
                            //          inside the SB, we can have a cache hit
                            //          - the cache entry is removed only after a successful memory write
                            //          - during the transaction, the entry is kept in the cache
                            //      (c) If the cache finished writing to memory, we will have a cache miss, which is
                            //          the correct bahaviour
                            cpuRequest.ready = TRUE;
                            cpuRequest.dataFromCache = cacheHitData;
                        end else begin
                            // (3) cache miss, fall back to cache query
                            `ASSERT(nextState == INTERRUPTING);
                        end
                    end
                end else begin : WriteRequestDeligate
                    // We deligate all CPU write requests to the store buffer, the write request
                    //   NEVER goes staright to the cache bypassing the store buffer
                    cpuRequest.ready = sbCanWrite;
                    sbWriteAddr = cpuRequest.addr;
                    sbWriteData = cpuRequest.dataToCache;
                    sbWriteDataLen = cpuRequest.dataLen;
                    sbWriteRequest = TRUE;
                end
            end else if (currentState == INTERRUPTED) begin
                // (3 - Continued) Cache miss, wait for SB draining to be interrupted
                //     Since the store buffer is constantly using the cache request to drain,
                //     the cache request line is busy
                if (sbInterruptedQ) begin
                    // deligate to the cache
                    cpuRequest.ready = deligatedCpuRequest.ready;
                    cpuRequest.failed = deligatedCpuRequest.failed;
                    cpuRequest.dataFromCache = deligatedCpuRequest.dataFromCache;
                    deligatedCpuRequest.request = TRUE;
                    deligatedCpuRequest.isRead = TRUE;
                    deligatedCpuRequest.invalidateAll = cpuRequest.invalidateAll;
                    deligatedCpuRequest.addr = cpuRequest.addr;
                    deligatedCpuRequest.dataToCache = '0;
                    deligatedCpuRequest.dataLen = cpuRequest.dataLen;
                end
            end
        end

        if (deligatedCpuRequest.request == sbCacheWriteOnlyRequest.master.request &&
            deligatedCpuRequest.isRead == FALSE &&
            deligatedCpuRequest.invalidateAll == FALSE &&
            deligatedCpuRequest.addr == sbCacheWriteOnlyRequest.addr &&
            deligatedCpuRequest.dataToCache == sbCacheWriteOnlyRequest.dataToCache &&
            deligatedCpuRequest.dataLen == sbCacheWriteOnlyRequest.dataLen) begin
            `SB_FRONTEND_DEBUG_PRINT(("[SB FRONT]: @%0d: Fallback to draining", DEBUG_tick));
        end
    end

    // debug metrices
    word_t DEBUG_reqWaits;
    word_t DEBUG_cyclesReqWaits;
    word_t DEBUG_cyclesInterruptWaits;
    word_t DEBUG_cyclesCacheWaits;
    word_t DEBUG_sbHit;
    word_t DEBUG_cacheHit;
    word_t DEBUG_tick;
    always_ff @(posedge clk) begin
        DEBUG_tick <= DEBUG_tick + 1;
        if (currentState == IDLE) begin
            if (cpuRequest.request && cpuRequest.isRead) begin
                if (sbIsHit) begin
                    DEBUG_sbHit <= DEBUG_sbHit + 1;
                end else if (cacheIsHit) begin
                    DEBUG_cacheHit <= DEBUG_cacheHit + 1;
                end
            end
        end
        if (currentState != IDLE) begin
            DEBUG_cyclesReqWaits <= DEBUG_cyclesReqWaits + 1;
        end
        if (currentState == INTERRUPTING) begin
            DEBUG_cyclesInterruptWaits <= DEBUG_cyclesInterruptWaits + 1;
        end
        if (currentState == INTERRUPTED) begin
            DEBUG_cyclesCacheWaits <= DEBUG_cyclesCacheWaits + 1;
        end
        if (currentState == INTERRUPTED && nextState == IDLE) begin
            DEBUG_reqWaits <= DEBUG_reqWaits + 1;
        end
    end

endmodule
