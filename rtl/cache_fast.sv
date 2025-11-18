`timescale 1ns / 1ps

import pkg_global_defs::*;
import pkg_riscv_instructions::*;

// `define CACHE_DEBUG_PRINT(x) $display({$sformatf x})
`define CACHE_DEBUG_PRINT(x)

module cache_fast (
    input logic clk,
    cache_request_if.slave cpuRequest,
    mem_request_if.master memRequest
);

    // // data line: 128-bit (16 bytes)
    // # of sets: 8 -> 3-bit addressing
    // # of ways: 2
    // offset within the cacheline: 4-bit
    //  - 128 bits within the cache line => 16 bytes => 4-bit addressing
    // [tag][set][offset]
    typedef struct {
        logic [24:0]  tag;    // 25 bits de tag
        logic [127:0] data;   // 16 bytes = 128 bits
        bool_t        valid;
        bool_t        dirty;
    } cache_line_t;

    typedef cache_line_t cache_set_t[2];  //2 way associative
    typedef cache_set_t cache_t[8];  // 8 sets
    typedef struct {bool_t lastUsed;} cache_lru_policy_t;
    typedef struct packed {
        logic [24:0] tag;     // 25-bit tag
        logic [2:0]  setIdx;  // 3-bit set address (8 sets)
        logic [3:0]  offset;  // 4-bit byte offset address
    } addr_access_t;

    // NOTE: here we assume that input cpuRequest.* stays unchanged
    //       as long as cpuRequest.request is asserted

    typedef enum logic [1:0] {
        IDLE,
        EVICT_WAIT,
        REFILL_WAIT,
        WRITEBACK
    } cache_state_t;

    cache_state_t currentState;
    cache_state_t nextState;

    cache_t cacheMem;
    cache_lru_policy_t policyMetadata[8];  // 8 sets

    logic targetWayIdx;
    word_t targetData;
    bool_t isHit, isSetFull, isVictimDirty;

    initial begin
        // currentState = IDLE;
        // nextState    = IDLE;
        for (int i = 0; i < 8; i++) begin
            for (int j = 0; j < 2; j++) begin
                cacheMem[i][j].valid = 1'b0;
                cacheMem[i][j].dirty = 1'b0;
            end
        end
        // isHit = 1'b0;
        // isSetFull = 1'b0;
    end

    addr_access_t targetAddr;
    assign targetAddr = cpuRequest.addr;
    cache_set_t set;
    cache_line_t way0, way1;
    addr_access_t victimAddr;
    cacheline_data_t victimLine;
    logic [2:0] DEBUG_setIdx;
    assign DEBUG_setIdx = targetAddr.setIdx;
    always_comb begin : LookupAndVictimSelectionLogic
        // 2-way
        set = cacheMem[targetAddr.setIdx];
        way0 = set[0];
        way1 = set[1];
        victimAddr = '0;
        victimLine = '0;
        targetWayIdx = '0;
        isVictimDirty = FALSE;
        isSetFull = FALSE;
        isHit = FALSE;
        if (cpuRequest.request) begin
            if (way0.valid && way0.tag == targetAddr.tag) begin
                targetWayIdx = 0;
                isHit = TRUE;
            end else if (way1.valid && way1.tag == targetAddr.tag) begin
                targetWayIdx = 1;
                isHit = TRUE;
            end else begin
                isSetFull = way0.valid && way1.valid;
                if (isSetFull) begin
                    targetWayIdx = ~policyMetadata[targetAddr.setIdx].lastUsed;
                    victimAddr.tag = set[targetWayIdx].tag;
                    victimAddr.setIdx = targetAddr.setIdx;
                    victimAddr.offset = 0;
                    victimAddr = victimAddr;
                    isVictimDirty = set[targetWayIdx].dirty;
                    victimLine = set[targetWayIdx].data;
                end else if (!way0.valid) begin
                    targetWayIdx = 0;
                end else begin
                    targetWayIdx = 1;
                end
            end
        end
        `CACHE_DEBUG_PRINT(
            ("@%d: targetAddr: %h, targetWayIdx: %b, isHit: %b, isSetFull: %b", DEBUG_tick,
                 targetAddr, targetWayIdx, isHit, isSetFull));
        `CACHE_DEBUG_PRINT(
            ("@%d: victimAddr: %h, victimLine: %h, isVictimDirty: %b", DEBUG_tick, victimAddr,
                 victimLine, isVictimDirty));
    end


    always_comb begin : DebugPrint
        for (int i = 0; i < 8; i++) begin
            `CACHE_DEBUG_PRINT(
                ("@%d: Set %0d: Way 0 - valid: %b, dirty: %b, tag: %h, data: %h", DEBUG_tick,
                     i, cacheMem[i][0].valid, cacheMem[i][0].dirty, cacheMem[i][0].tag,
                     cacheMem[i][0].data));
            `CACHE_DEBUG_PRINT(
                ("@%d: Set %0d: Way 1 - valid: %b, dirty: %b, tag: %h, data: %h", DEBUG_tick,
                     i, cacheMem[i][1].valid, cacheMem[i][1].dirty, cacheMem[i][1].tag,
                     cacheMem[i][1].data));
        end
    end

    // TODO: use combinational logic?
    always_ff @(posedge clk) begin : PolicyUpdate
        // Only update after a successful read/write
        if (currentState == IDLE && isHit) begin
            assert (cpuRequest.request);
            policyMetadata[targetAddr.setIdx].lastUsed <= targetWayIdx;
        end
    end

    logic [31:0] DEBUG_tick;
    always_ff @(posedge clk) begin : StateUpdate
        if (cpuRequest.invalidateAll) begin
            // TODO: when it is invalidating the cache,  should we flush 
            //       the cachelines, or should it be done in another `flush` instruction?
            currentState <= IDLE;
            for (int i = 0; i < 8; i++) begin
                for (int j = 0; j < 2; j++) begin
                    cacheMem[i][j].valid <= 1'b0;
                    cacheMem[i][j].dirty <= 1'b0;
                end
            end
        end else begin
            currentState <= nextState;
        end
        DEBUG_tick <= DEBUG_tick + 1;
    end

    always_comb begin : NextStateLogic
        `CACHE_DEBUG_PRINT(("@%d: =============== NextStateLogic run ===============", DEBUG_tick));
        nextState = currentState;
        case (currentState)
            IDLE: begin
                if (cpuRequest.request && !isHit) begin
                    if (isSetFull && isVictimDirty) begin
                        nextState = EVICT_WAIT;
                    end else begin
                        nextState = REFILL_WAIT;
                    end
                end
            end
            EVICT_WAIT: begin
                assert (isSetFull && isVictimDirty);
                if (memRequest.ready) begin
                    nextState = REFILL_WAIT;
                end else begin
                    assert (nextState == EVICT_WAIT);
                    assert (memRequest.request);
                    assert (!memRequest.isRead);
                    assert (memRequest.addr == victimAddr);
                    assert (memRequest.dataToMem == victimLine);

                end
            end
            REFILL_WAIT: begin
                if (memRequest.ready) begin
                    if (cpuRequest.isRead) begin
                        `CACHE_DEBUG_PRINT(("@%d: decided: REFILL_WAIT -> IDLE", DEBUG_tick));
                        nextState = IDLE;
                    end else begin
                        `CACHE_DEBUG_PRINT(("@%d: decided: REFILL_WAIT -> WRITEBACK", DEBUG_tick));
                        nextState = WRITEBACK;
                    end
                end else begin
                    assert (nextState == REFILL_WAIT);
                    `CACHE_DEBUG_PRINT(("@%d: decided: REFILL_WAIT -> REFILL_WAIT", DEBUG_tick));
                    `CACHE_DEBUG_PRINT(("@%d: checking assert", DEBUG_tick));
                    `CACHE_DEBUG_PRINT(
                        ("@%d: checking assert: memRequest.request = %b", DEBUG_tick,
                             memRequest.request));
                    `CACHE_DEBUG_PRINT(
                        ("@%d: checking assert: memRequest.isRead = %b", DEBUG_tick,
                             memRequest.isRead));
                    `CACHE_DEBUG_PRINT(
                        ("@%d: checking assert: memRequest.addr = %h", DEBUG_tick,
                             memRequest.addr));
                    assert (memRequest.request);
                    assert (memRequest.isRead);
                    assert (memRequest.addr == targetAddr);
                end
            end
            WRITEBACK: begin
                nextState = IDLE;
            end
            default: begin
                assert (FALSE);
            end
        endcase
        `CACHE_DEBUG_PRINT(
            ("@%d: currentState = %d, nextState = %d", DEBUG_tick, currentState, nextState));
        // if (currentState != IDLE) begin
        //     assert (cpuRequest.request);
        //     assert (!cpuRequest.invalidateAll);
        // end
    end

    // NOTE: do not use combinational logic
    // at the rising edge of the clock, a memory request is ready (reponseded):
    // 1. MemoryRequestLogic: (REFILL_WAIT -> REFILL_WAIT): keep memRequest
    // 2. NextStateLogic: if (memRequest.ready): decide REFILL_WAIT -> IDLE
    // 3. MemoryRequestLogic: (REFILL_WAIT -> IDLE): drop memRequest (hence ~memRequest.ready)
    // 4. NextStateLogic: (!memRequest.ready): decide REFILL_WAIT -> REFILL_WAIT
    always_ff @(posedge clk) begin : MemoryRequestLogic
        `CACHE_DEBUG_PRINT(
            ("@%d: =============== MemoryRequestLogic run ===============", DEBUG_tick));
        memRequest.request <= FALSE;
        memRequest.isRead <= FALSE;
        memRequest.addr <= '0;
        memRequest.dataToMem <= '0;
        if (nextState == EVICT_WAIT) begin
            assert (currentState == IDLE || currentState == EVICT_WAIT);
            if (currentState == IDLE) begin
                `CACHE_DEBUG_PRINT(("@%d: EVICT_WAIT -> IDLE edge", DEBUG_tick));
            end else begin
                `CACHE_DEBUG_PRINT(("@%d: EVICT_WAIT -> EVICT_WAIT edge", DEBUG_tick));
            end
            memRequest.request <= TRUE;
            memRequest.isRead <= FALSE;
            memRequest.addr <= victimAddr;
            memRequest.dataToMem <= victimLine;
            `CACHE_DEBUG_PRINT(
                ("@%d: memRequest.request = %d, memRequest.isRead = %d, memRequest.addr = %d, memRequest.dataToMem = %d",
                DEBUG_tick, memRequest.request, memRequest.isRead, memRequest.addr,
                memRequest.dataToMem));
        end else if (nextState == REFILL_WAIT) begin
            assert (currentState == EVICT_WAIT || currentState == REFILL_WAIT ||
                    currentState == IDLE);

            if (currentState == EVICT_WAIT) begin
                `CACHE_DEBUG_PRINT(("@%d: EVICT_WAIT -> REFILL_WAIT edge", DEBUG_tick));
            end else if (currentState == REFILL_WAIT) begin
                `CACHE_DEBUG_PRINT(("@%d: REFILL_WAIT -> REFILL_WAIT edge", DEBUG_tick));
            end else begin
                `CACHE_DEBUG_PRINT(("@%d: IDLE -> REFILL_WAIT edge", DEBUG_tick));
            end

            memRequest.request <= TRUE;
            memRequest.isRead <= TRUE;
            memRequest.addr <= targetAddr;
            `CACHE_DEBUG_PRINT(
                ("@%d: memRequest.request = %d, memRequest.isRead = %d, memRequest.addr = %d, memRequest.dataToMem = %d",
                DEBUG_tick, memRequest.request, memRequest.isRead, memRequest.addr,
                memRequest.dataToMem));
        end else begin
            `CACHE_DEBUG_PRINT(("@%d dropping memory request", DEBUG_tick));
            `CACHE_DEBUG_PRINT(
                ("@%d: dropping memory request: currrentState=%d, nextState=%d", DEBUG_tick,
                     currentState, nextState));
        end
    end

    always_comb begin : DEBUG_PrintRequests
        `CACHE_DEBUG_PRINT(
            (
            "@%d: CpuRequest - req: %b, ready: %b, isRead: %b, addr: %h, dataToCache: %h, dataFromCache: %h",
            DEBUG_tick, cpuRequest.request, cpuRequest.ready, cpuRequest.isRead, cpuRequest.addr,
            cpuRequest.dataToCache, cpuRequest.dataFromCache));
        `CACHE_DEBUG_PRINT(
            (
            "@%d: MemRequest - req: %b, ready: %b, isRead: %b, addr: %h, dataToMem: %h, dataFromMem: %h",
            DEBUG_tick, memRequest.request, memRequest.ready, memRequest.isRead, memRequest.addr,
            memRequest.dataToMem, memRequest.dataFromMem));
    end


    always_ff @(posedge clk) begin : CacheMemoryUpdate
        `CACHE_DEBUG_PRINT(
            ("@%d [CACHE MEMORY UPDATE]: request=%d, currentState=%d, nextState=%d, isHit=%d",
                 DEBUG_tick, cpuRequest.request, currentState, nextState, isHit));

        if (cpuRequest.request) begin
            `CACHE_DEBUG_PRINT(
                (
                "@%d [CACHE MEMORY UPDATE]: shouldWriteback=%d", DEBUG_tick,
                (currentState == IDLE || currentState == WRITEBACK) && nextState == IDLE && !cpuRequest.isRead));
            `CACHE_DEBUG_PRINT(
                (
                "@%d [CACHE MEMORY UPDATE]: (currentState == IDLE || currentState == WRITEBACK)=",
                DEBUG_tick, (currentState == IDLE || currentState == WRITEBACK)));
            `CACHE_DEBUG_PRINT(
                ("@%d [CACHE MEMORY UPDATE]: !cpuRequest.isRead=%d, nextState == IDLE=%d",
                     DEBUG_tick, !cpuRequest.isRead, nextState == IDLE));
            if (currentState == REFILL_WAIT && nextState != REFILL_WAIT) begin
                assert (!isHit);
                assert (nextState == IDLE || nextState == WRITEBACK);
                cacheMem[targetAddr.setIdx][targetWayIdx].data  <= memRequest.dataFromMem;
                cacheMem[targetAddr.setIdx][targetWayIdx].tag   <= targetAddr.tag;
                cacheMem[targetAddr.setIdx][targetWayIdx].valid <= 1'b1;
                cacheMem[targetAddr.setIdx][targetWayIdx].dirty <= 1'b0;
            end else if ((currentState == IDLE || currentState == WRITEBACK) &&
                         nextState == IDLE && !cpuRequest.isRead) begin
                // NOTE: the written memory is only visible in the next cycle
                //       this is fine since we did a bypass in the `RequestResponse` block
                `CACHE_DEBUG_PRINT(
                    ("@%d: Writing data to cache: 0x%h at offset %0d", DEBUG_tick,
                                   cpuRequest.dataToCache, targetAddr.offset));
                cacheMem[targetAddr.setIdx][targetWayIdx].data[targetAddr.offset*8+:32] <= cpuRequest.dataToCache;
                cacheMem[targetAddr.setIdx][targetWayIdx].dirty <= 1'b1;
            end
        end
    end

    // use this tmp variable to make Verilator happy
    logic [127:0] tmpDataFromMem;
    assign tmpDataFromMem = memRequest.dataFromMem;
    always_comb begin : RequestResponse
        cpuRequest.failed = FALSE;  // never fails
        cpuRequest.ready = FALSE;
        cpuRequest.dataFromCache = '0;
        if (cpuRequest.request && nextState == IDLE) begin
            cpuRequest.ready = TRUE;
            if (cpuRequest.isRead) begin
                if (isHit) begin
                    // assert (currentState == IDLE);
                    cpuRequest.dataFromCache = cacheMem[targetAddr.setIdx][targetWayIdx].data[targetAddr.offset*8+:32];
                end else begin
                    assert (currentState == REFILL_WAIT);
                    // NOTE: bypass
                    //       here, we cannot use cacheMem because it has NOT been updated yet
                    //       it will be visible in the next cycle, i.e. `currentState == DONE`
                    //       However, if we assigned the response at `DONE`, we would have 
                    //       wasted a cycle for the response to be visible to the CPU
                    `CACHE_DEBUG_PRINT(
                        ("@%d: Bypass data from mem: 0x%h", DEBUG_tick,
                                       tmpDataFromMem[targetAddr.offset*8+:32]));
                    cpuRequest.dataFromCache = tmpDataFromMem[targetAddr.offset*8+:32];
                end
            end
        end
    end

    // always_comb begin : Exception
    //     assert (cpuRequest.addr < DATA_MEM_SIZE)
    //     else
    //         `CACHE_DEBUG_PRINT(
    //             "Invalid memory access @%h while max size is %h",
    //             cpuRequest.addr + 15,
    //             DATA_MEM_SIZE
    //         );
    // end


endmodule
