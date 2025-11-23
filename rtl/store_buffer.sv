`define SB_DEBUG_PRINT(x) $display({$sformatf x})
// `define SB_DEBUG_PRINT(x)

module store_buffer
    import pkg_global_defs::*;
(
    input logic clk,
    // read combinationally
    input addr_t readAddr,
    output word_t readData,
    output bool_t readHit,
    // write sequentially
    output bool_t sbCanWrite,
    input bool_t writeRequest,
    input addr_t writeAddr,
    input word_t writeData,
    input mem_stlen_t writeDataLen,
    // interrupt draining
    input bool_t interrupt,
    output bool_t interrupted,
    // interface to cache
    cache_writeonly_request_if.master cacheRequest
);

    typedef struct {
        bool_t valid;  // should be consistent with the valid range [oldest, nextYoungest) mod SIZE
        addr_t addr;
        word_t data;
        mem_stlen_t dataLen;
    } store_buffer_entry_t;

    typedef enum logic [2:0] {
        IDLE,
        DRAINING,
        DRAINING_INTERRUPTING,
        DRAINING_INTERRUPTED
    } store_buffer_state_t;

    store_buffer_state_t currentState, nextState;

    store_buffer_entry_t buffer[4];
    // NOTE: Wrap-around Logic
    //      wrap-around is guaranteed by overflow/underflow
    //      since the buffer size is BUFFER_SIZE = 2^(ADDR_SIZE)
    logic [1:0] oldest, nextYoungest;

    bool_t isFull, isEmpty, hasOnlyOneElement;
    assign isEmpty = oldest == nextYoungest && !isFull;
    assign sbCanWrite = !isFull;
    initial isFull = FALSE;

    bool_t isHit;
    logic [1:0] hitIdx;

    always_comb begin : StoreBufferHitLogic
        `SB_DEBUG_PRINT(("@%d: ==== StoreBufferHitLogic run ====", DEBUG_tick));
        `SB_DEBUG_PRINT(("@%d: readAddr=0x%h", DEBUG_tick, readAddr));
        `SB_DEBUG_PRINT(("@%d: oldest=%0d, nextYoungest=%0d", DEBUG_tick, oldest, nextYoungest));
        for (int i = 0; i < 4; i++) begin
            `SB_DEBUG_PRINT(
                ("@%d: Buffer[%0d]: valid=%0b, addr=0x%h, data=0x%h, len=%0d", DEBUG_tick, i,
                buffer[i].valid, buffer[i].addr, buffer[i].data, buffer[i].dataLen));
        end
        isHit  = FALSE;
        hitIdx = '0;
        // prefer younger hits
        if (buffer[2'(nextYoungest-1)].valid && buffer[2'(nextYoungest-1)].addr == readAddr) begin
            isHit  = TRUE;
            hitIdx = 2'(nextYoungest - 1);
        end else if (buffer[2'(nextYoungest-2)].valid &&
                     buffer[2'(nextYoungest-2)].addr == readAddr) begin
            isHit  = TRUE;
            hitIdx = 2'(nextYoungest - 2);
        end else if (buffer[2'(nextYoungest-3)].valid &&
                     buffer[2'(nextYoungest-3)].addr == readAddr) begin
            isHit  = TRUE;
            hitIdx = 2'(nextYoungest - 3);
        end else if (buffer[2'(nextYoungest-4)].valid &&
                     buffer[2'(nextYoungest-4)].addr == readAddr) begin
            isHit  = TRUE;
            hitIdx = 2'(nextYoungest - 4);
        end
        `SB_DEBUG_PRINT(
            ("@%d: Read addr=0x%h data=0x%h hit=%b", DEBUG_tick, readAddr,
            isHit ? buffer[hitIdx].data : '0, isHit));
        `SB_DEBUG_PRINT(
            ("@%d: readAddr=0x%h readHit=%0b, readData=0x%h", DEBUG_tick, readAddr, isHit, isHit ? buffer[hitIdx].data : '0));
    end

    assign readHit  = isHit;
    assign readData = isHit ? buffer[hitIdx].data : '0;

    always_comb begin : NextStateLogic
        `SB_DEBUG_PRINT(("@%d: ==== NextStateLogic run ====", DEBUG_tick));
        `SB_DEBUG_PRINT(("@%d: oldest=%0d, nextYoungest=%0d", DEBUG_tick, oldest, nextYoungest));
        `SB_DEBUG_PRINT(("@%d: isEmpty=%0b, isFull=%0b", DEBUG_tick, isEmpty, isFull));
        `SB_DEBUG_PRINT(("@%d: currentState=%0d", DEBUG_tick, currentState));
        nextState = currentState;
        case (currentState)
            IDLE: begin
                // assert (!cacheRequest.request);
                if (!interrupt && !isEmpty) begin
                    // BUG FIX: use (!empty || writeRequest) would need a bypass logic in cache request
                    `SB_DEBUG_PRINT(("@%d: decided: IDLE -> DRAINING", DEBUG_tick));
                    nextState = DRAINING;
                end
            end
            DRAINING: begin
                assert (cacheRequest.request);
                if (isEmpty) begin
                    `SB_DEBUG_PRINT(("@%d: decided: DRAINING -> IDLE", DEBUG_tick));
                    nextState = IDLE;
                end else if (interrupt) begin
                    if (!cacheRequest.ready) begin
                        `SB_DEBUG_PRINT(
                            ("@%d: decided: DRAINING -> DRAINING_INTERRUPTING", DEBUG_tick));
                        nextState = DRAINING_INTERRUPTING;
                    end else begin
                        `SB_DEBUG_PRINT(
                            ("@%d: decided: DRAINING -> DRAINING_INTERRUPTED", DEBUG_tick));
                        nextState = DRAINING_INTERRUPTED;
                    end
                end else if (cacheRequest.ready) begin
                    assert (cacheRequest.addr == buffer[oldest].addr);
                    assert (cacheRequest.dataToCache == buffer[oldest].data);
                    assert (cacheRequest.dataLen == buffer[oldest].dataLen);
                    if (buffer[2'(oldest+1)].valid) begin
                        `SB_DEBUG_PRINT(("@%d: decided: DRAINING -> DRAINING", DEBUG_tick));
                        nextState = DRAINING;
                    end else begin
                        `SB_DEBUG_PRINT(("@%d: decided: DRAINING -> IDLE", DEBUG_tick));
                        nextState = IDLE;
                    end
                end
            end
            DRAINING_INTERRUPTING: begin
                if (cacheRequest.ready) begin
                    `SB_DEBUG_PRINT(
                        ("@%d: decided: DRAINING_INTERRUPTING -> DRAINING_INTERRUPTED", DEBUG_tick));
                    nextState = DRAINING_INTERRUPTED;
                end
            end
            DRAINING_INTERRUPTED: begin
                if (!interrupt) begin
                    if (!isEmpty) begin
                        // BUG FIX: to use (!empty || writeRequest) would need a bypass logic in cache request
                        `SB_DEBUG_PRINT(
                            ("@%d: decided: DRAINING_INTERRUPTED -> DRAINING", DEBUG_tick));
                        nextState = DRAINING;
                    end else begin
                        `SB_DEBUG_PRINT(("@%d: decided: DRAINING_INTERRUPTED -> IDLE", DEBUG_tick));
                        nextState = IDLE;
                    end
                end
            end
            default: begin
                assert (FALSE);
            end
        endcase
    end

    always_ff @(posedge clk) begin : StateUpdateLogic
        `SB_DEBUG_PRINT(("@%d: ==== StateUpdateLogic run ====", DEBUG_tick));
        `SB_DEBUG_PRINT(
            ("@%d: currentState=%0d, nextState=%0d", DEBUG_tick, currentState, nextState));
        currentState <= nextState;
    end

    always_comb begin : InterruptSuccessLogic
        interrupted = FALSE;
        if (interrupt) begin
            if (currentState == DRAINING_INTERRUPTED) begin
                interrupted = TRUE;
            end else if (currentState == IDLE && nextState == IDLE) begin
                assert (isEmpty);
                interrupted = TRUE;
            end
        end
    end

    // TODO: clean up the logic
    always_ff @(posedge clk) begin : DrainingRequestAndDequeueLogic
        `SB_DEBUG_PRINT(("@%d: ==== DrainingRequestAndDequeueLogic run ====", DEBUG_tick));
        `SB_DEBUG_PRINT(
            ("@%d: currentState=%0d, nextState=%0d", DEBUG_tick, currentState, nextState));
        `SB_DEBUG_PRINT(
            ("@%d: cacheRequest before logic: READY=%0b request=%0b addr=0x%h data=0x%h len=%0d", DEBUG_tick,
            cacheRequest.ready, cacheRequest.request, cacheRequest.addr, cacheRequest.dataToCache,
            cacheRequest.dataLen));
        if (currentState == DRAINING && (nextState == DRAINING || nextState == IDLE)) begin
            // FIXME: confused request
            // Make sure the response is for our current request
            assert (cacheRequest.request);
            `SB_DEBUG_PRINT(
                ("@%d: Draining ongoing addr=0x%h data=0x%h len=%0d", DEBUG_tick, buffer[oldest].addr,
                buffer[oldest].data, buffer[oldest].dataLen));
            `SB_DEBUG_PRINT(
                ("@%d: cacheRequest: ready=%0b addr=0x%h data=0x%h len=%0d", DEBUG_tick,
                cacheRequest.ready, cacheRequest.addr, cacheRequest.dataToCache,
                cacheRequest.dataLen));
            assert (cacheRequest.addr == buffer[oldest].addr);
            assert (cacheRequest.dataToCache == buffer[oldest].data);
            assert (cacheRequest.dataLen == buffer[oldest].dataLen);
            assert (buffer[oldest].valid);
            if (cacheRequest.ready) begin
                `SB_DEBUG_PRINT(("@%d: Draining completed for oldest entry", DEBUG_tick));
                `SB_DEBUG_PRINT(
                    ("@%d: current oldest=%0d, next oldest=%0d, next oldest valid=%0b",
                    DEBUG_tick, oldest, 2'(oldest + 1), buffer[2'(oldest+1)].valid));
                // our current `oldest` store operation is written to cache
                oldest <= 2'(oldest + 1);  // advance the `oldest` pointer
                isFull <= FALSE;  // we definitely have space now
                buffer[oldest].valid <= FALSE;
                if (buffer[2'(oldest+1)].valid) begin
                    assert (nextState == DRAINING);
                    `SB_DEBUG_PRINT(
                        ("@%d: Draining next oldest addr=0x%h data=0x%h len=%0d",
                        DEBUG_tick, buffer[2'(oldest+1)].addr, buffer[2'(oldest+1)].data,
                        buffer[2'(oldest+1)].dataLen));
                    // TODO: assert within valid range
                    `SB_DEBUG_PRINT(
                        ("@%d: Issuing next cache request", DEBUG_tick));
                    `SB_DEBUG_PRINT(
                        ("@%d: cacheRequest before issuing next: READY=%0b request=%0b addr=0x%h data=0x%h len=%0d", DEBUG_tick,
                        cacheRequest.ready, cacheRequest.request, cacheRequest.addr, cacheRequest.dataToCache,
                        cacheRequest.dataLen));
                    `SB_DEBUG_PRINT(
                        ("@%d: next request addr=0x%h data=0x%h len=%0d", DEBUG_tick,
                        buffer[2'(oldest+1)].addr, buffer[2'(oldest+1)].data,
                        buffer[2'(oldest+1)].dataLen));
                    // kick start next request
                    cacheRequest.request <= TRUE;
                    cacheRequest.addr <= buffer[2'(oldest+1)].addr;
                    cacheRequest.dataToCache <= buffer[2'(oldest+1)].data;
                    cacheRequest.dataLen <= buffer[2'(oldest+1)].dataLen;
                end else begin
                    assert (2'(oldest + 1) == nextYoungest);
                    assert (nextState == IDLE);
                end
            end
        end else if (currentState != DRAINING && nextState == DRAINING) begin
            `SB_DEBUG_PRINT(
                ("@%d: Draining first oldest addr=0x%h data=0x%h len=%0d",
                DEBUG_tick, buffer[oldest].addr, buffer[oldest].data, buffer[oldest].dataLen));
            // enterting draining
            assert (currentState == IDLE || currentState == DRAINING_INTERRUPTED);
            // kick start request
            cacheRequest.request <= TRUE;
            cacheRequest.addr <= buffer[oldest].addr;
            cacheRequest.dataToCache <= buffer[oldest].data;
            cacheRequest.dataLen <= buffer[oldest].dataLen;
        end else if (currentState == DRAINING && nextState == DRAINING_INTERRUPTING) begin
            // interrupted while draining, the request is still going
            // we keep the request
        end else if (currentState == DRAINING && nextState == DRAINING_INTERRUPTED) begin
            `SB_DEBUG_PRINT(("@%d: Draining interrupted, dropping future requests", DEBUG_tick));
            // interrupted while draining, the request HAPPENED to finish
            // we drop future requests to prevent writing to the cache
            cacheRequest.request <= FALSE;
        end else if (currentState == DRAINING_INTERRUPTING && nextState == DRAINING_INTERRUPTED) begin
            assert (cacheRequest.ready);
            `SB_DEBUG_PRINT(("@%d: Draining interrupted after request completed", DEBUG_tick));
            oldest <= 2'(oldest + 1);  // advance the `oldest` pointer
            isFull <= FALSE;  // we definitely have space now
            buffer[oldest].valid <= FALSE;
        end

        if (nextState == IDLE) begin
            cacheRequest.request <= FALSE;
        end
        // print request state
        `SB_DEBUG_PRINT(
            ("@%d: cacheRequest after logic: READY=%0b request=%0b addr=0x%h data=0x%h len=%0d", DEBUG_tick,
            cacheRequest.ready, cacheRequest.request, cacheRequest.addr, cacheRequest.dataToCache,
            cacheRequest.dataLen));
    end

    always_ff @(posedge clk) begin : EnqueueLogic
        `SB_DEBUG_PRINT(("@%d: ==== EnqueueLogic run ====", DEBUG_tick));
        `SB_DEBUG_PRINT(("@%d: isEmpty=%0b, isFull=%0b", DEBUG_tick, isEmpty, isFull));
        `SB_DEBUG_PRINT(
            ("@%d: writeRequest=%0b, writeAddr=0x%h, writeData=0x%h, writeDataLen=%0d",
            DEBUG_tick, writeRequest, writeAddr, writeData, writeDataLen));
        if (writeRequest && !isFull) begin
            `SB_DEBUG_PRINT(
                ("@%d: Enqueueing writeRequest addr=0x%h data=0x%h len=%0d", DEBUG_tick, writeAddr, writeData, writeDataLen));
            assert (sbCanWrite);
            nextYoungest <= 2'(nextYoungest + 1);
            buffer[nextYoungest].valid <= TRUE;
            buffer[nextYoungest].addr <= writeAddr;
            buffer[nextYoungest].data <= writeData;
            buffer[nextYoungest].dataLen <= writeDataLen;
            if (2'(nextYoungest + 1) == oldest) begin
                isFull <= TRUE;
            end
        end
    end

    always_comb begin : DebugPrint
        `SB_DEBUG_PRINT(("@%d: ==== DebugPrint run ====", DEBUG_tick));
        `SB_DEBUG_PRINT(
            ("@%d: Buffer State: oldest=%0d, nextYoungest=%0d, isFull=%0b", DEBUG_tick, oldest,
            nextYoungest, isFull));
        for (int i = 0; i < 4; i++) begin
            `SB_DEBUG_PRINT(
                ("@%d: Buffer[%0d]: valid=%0b, addr=0x%h, data=0x%h, len=%0d", DEBUG_tick, i,
                buffer[i].valid, buffer[i].addr, buffer[i].data, buffer[i].dataLen));
        end
    end

    logic [31:0] DEBUG_tick;
    always_ff @(posedge clk) begin
        DEBUG_tick <= DEBUG_tick + 1;
    end

endmodule
