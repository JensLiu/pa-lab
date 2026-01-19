module data_cache_access_sequencer
    import pkg_virtual_memory::*;
    import pkg_global_defs::*;
(
    input clk_t clk,
    cache_request_if.slave cpuRequest,
    pw_cache_if.memory_controller pwRequest,
    cache_request_if.master cacheRequest
);

    // To avoid combinational loops, we use a state machine
    // pwCache.ready -> PW cache hit -> PW ready (bypass) -> PW page fault -> MMU ready -> cpuRequest
    // instead now we serve the cpuRequest, so NOT(pwCache.request) -> NOT(pwCache.ready)

    // The loop analysis is coarse-grain, but for simplicity, we just flop on TLB miss
    // and then let page walker take control of the access line.
    // (It's a miss anyway, let's just add another cycle of delay and be correct)

    typedef enum logic [1:0] {
        IDLE,
        PW_WAIT,
        PW_DONE
    } state_t;

    state_t currentState, nextState;

    // Capture the cache response when ready
    word_t pw_rdata_reg;
    logic  pw_fault_reg;

    always_ff @(posedge clk) begin
        if (currentState == PW_WAIT && cacheRequest.ready) begin
            pw_rdata_reg <= cacheRequest.dataFromCache;
            pw_fault_reg <= cacheRequest.failed;
        end
    end

    always_comb begin
        nextState = currentState;
        case (currentState)
            IDLE: begin
                if (!cpuRequest.request && pwRequest.req) begin
                    nextState = PW_WAIT;
                end
            end
            PW_WAIT: begin
                assert (pwRequest.req);
                if (cacheRequest.ready) begin
                    nextState = PW_DONE;
                end
            end
            PW_DONE: begin
                nextState = IDLE;
            end
            default: begin
                assert (FALSE);
            end
        endcase
    end

    always_ff @(posedge clk) begin
        currentState <= nextState;
    end

    always_comb begin
        cpuRequest.ready = FALSE;
        cpuRequest.failed = FALSE;
        cpuRequest.dataFromCache = '0;

        pwRequest.ready = FALSE;
        pwRequest.rdata = '0;
        pwRequest.fault = FALSE;

        cacheRequest.request = FALSE;
        cacheRequest.isRead = FALSE;
        cacheRequest.invalidateAll = FALSE;
        cacheRequest.addr = '0;
        cacheRequest.dataToCache = '0;
        cacheRequest.dataLen = MEM_STLEN_WORD;

        // NOTE: request should NOT drop request depending on the ready bit
        // Priority: CPU request > page walker request
        if (currentState == IDLE) begin
            cacheRequest.request = cpuRequest.request;
            cacheRequest.isRead = cpuRequest.isRead;
            cacheRequest.invalidateAll = cpuRequest.invalidateAll;
            cacheRequest.addr = cpuRequest.addr;
            cacheRequest.dataToCache = cpuRequest.dataToCache;
            cacheRequest.dataLen = cpuRequest.dataLen;
            cpuRequest.ready = cacheRequest.ready;
            cpuRequest.failed = cacheRequest.failed;
            cpuRequest.dataFromCache = cacheRequest.dataFromCache;
        end else if (currentState == PW_WAIT) begin
            cacheRequest.request = pwRequest.req;
            cacheRequest.isRead = ~pwRequest.is_write;
            cacheRequest.invalidateAll = FALSE;
            cacheRequest.addr = pwRequest.addr;
            cacheRequest.dataToCache = pwRequest.wdata;
            cacheRequest.dataLen = MEM_STLEN_WORD;
            // Do NOT assign pwRequest.ready here - wait for PW_DONE state
        end else if (currentState == PW_DONE) begin
            // Ready comes directly from state (registered), breaking the comb loop
            pwRequest.ready = TRUE;
            pwRequest.rdata = pw_rdata_reg;
            pwRequest.fault = pw_fault_reg;
        end
    end

endmodule
