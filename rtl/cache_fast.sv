`timescale 1ns / 1ps

import pkg_global_defs::*;
import pkg_riscv_instructions::*;

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


module cache_fast (
    input logic clk,
    cache_request_if.slave cpuRequest,
    mem_request_if.master memRequest
);

    // NOTE: here we assume that input cpuRequest.* stays unchanged
    //       as long as cpuRequest.request is asserted

    typedef enum logic [1:0] {
        IDLE,
        EVICT_WAIT,
        REFILL_WAIT,
        WRITEBACK
    } cache_state_t;

    cache_state_t currentState;
    /* verilator lint_off UNOPTFLAT */
    cache_state_t nextState;
    /* verilator lint_on UNOPTFLAT */

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
        $display("@%d: targetAddr: %h, targetWayIdx: %b, isHit: %b, isSetFull: %b", DEBUG_tick,
                 targetAddr, targetWayIdx, isHit, isSetFull);
        $display("@%d: victimAddr: %h, victimLine: %h, isVictimDirty: %b", DEBUG_tick, victimAddr,
                 victimLine, isVictimDirty);
    end


    always_comb begin : DebugPrint
        for (int i = 0; i < 8; i++) begin
            $display("@%d: Set %0d: Way 0 - valid: %b, dirty: %b, tag: %h, data: %h", DEBUG_tick,
                     i, cacheMem[i][0].valid, cacheMem[i][0].dirty, cacheMem[i][0].tag,
                     cacheMem[i][0].data);
            $display("@%d: Set %0d: Way 1 - valid: %b, dirty: %b, tag: %h, data: %h", DEBUG_tick,
                     i, cacheMem[i][1].valid, cacheMem[i][1].dirty, cacheMem[i][1].tag,
                     cacheMem[i][1].data);
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
                    assert (memRequest.request);
                    assert (!memRequest.isRead);
                    assert (memRequest.addr == victimAddr);
                    assert (memRequest.dataToMem == victimLine);
                end
            end
            REFILL_WAIT: begin
                if (memRequest.ready) begin
                    if (cpuRequest.isRead) begin
                        nextState = IDLE;
                    end else begin
                        nextState = WRITEBACK;
                    end
                end else begin
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
        $display("@%d: currentState = %d, nextState = %d", DEBUG_tick, currentState, nextState);
        // if (currentState != IDLE) begin
        //     assert (cpuRequest.request);
        //     assert (!cpuRequest.invalidateAll);
        // end
    end

    // NOTE: improvement: using combinational logic
    always_comb begin : MemoryRequestLogic
        memRequest.request = FALSE;
        memRequest.isRead = FALSE;
        memRequest.addr = '0;
        memRequest.dataToMem = '0;
        if (nextState == EVICT_WAIT) begin
            assert (currentState == IDLE || currentState == EVICT_WAIT);
            memRequest.request = TRUE;
            memRequest.isRead = FALSE;
            memRequest.addr = victimAddr;
            memRequest.dataToMem = victimLine;
        end else if (nextState == REFILL_WAIT) begin
            assert (currentState == EVICT_WAIT || currentState == REFILL_WAIT ||
                    currentState == IDLE);
            memRequest.request = TRUE;
            memRequest.isRead = TRUE;
            memRequest.addr = targetAddr;
        end
    end

    always_comb begin
        $display(
            "@%d: CpuRequest - req: %b, ready: %b, isRead: %b, addr: %h, dataToCache: %h, dataFromCache: %h",
            DEBUG_tick, cpuRequest.request, cpuRequest.ready, cpuRequest.isRead, cpuRequest.addr,
            cpuRequest.dataToCache, cpuRequest.dataFromCache);
        $display(
            "@%d: MemRequest - req: %b, ready: %b, isRead: %b, addr: %h, dataToMem: %h, dataFromMem: %h",
            DEBUG_tick, memRequest.request, memRequest.ready, memRequest.isRead, memRequest.addr,
            memRequest.dataToMem, memRequest.dataFromMem);
    end


    always_ff @(posedge clk) begin : CacheMemoryUpdate
        $display("@%d [CACHE MEMORY UPDATE]: request=%d, currentState=%d, nextState=%d, isHit=%d",
                 DEBUG_tick, cpuRequest.request, currentState, nextState, isHit);

        if (cpuRequest.request) begin
            $display(
                "@%d [CACHE MEMORY UPDATE]: shouldWriteback=%d", DEBUG_tick,
                (currentState == IDLE || currentState == WRITEBACK) && nextState == IDLE && !cpuRequest.isRead);
            $display(
                "@%d [CACHE MEMORY UPDATE]: (currentState == IDLE || currentState == WRITEBACK)=",
                DEBUG_tick, (currentState == IDLE || currentState == WRITEBACK));
            $display("@%d [CACHE MEMORY UPDATE]: !cpuRequest.isRead=%d, nextState == IDLE=%d",
                     DEBUG_tick, !cpuRequest.isRead, nextState == IDLE);
            if (currentState == REFILL_WAIT && nextState != REFILL_WAIT) begin
                assert (!isHit);
                assert (nextState == IDLE || nextState == WRITEBACK);
                cacheMem[targetAddr.setIdx][targetWayIdx].data  <= memRequest.dataFromMem;
                cacheMem[targetAddr.setIdx][targetWayIdx].tag   <= targetAddr.tag;
                cacheMem[targetAddr.setIdx][targetWayIdx].valid <= 1'b1;
                cacheMem[targetAddr.setIdx][targetWayIdx].dirty <= 1'b0;
            end else if ((currentState == IDLE || currentState == WRITEBACK)
                         && nextState == IDLE && !cpuRequest.isRead) begin
                // NOTE: the written memory is only visible in the next cycle
                //       this is fine since we did a bypass in the `RequestResponse` block
                $display("@%d: Writing data to cache: 0x%h at offset %0d", DEBUG_tick,
                         cpuRequest.dataToCache, targetAddr.offset);
                cacheMem[targetAddr.setIdx][targetWayIdx].data[targetAddr.offset*8+:32] <= cpuRequest.dataToCache;
                cacheMem[targetAddr.setIdx][targetWayIdx].dirty <= 1'b1;
            end
        end
    end

    // use this tmp variable to make Verilator happy
    logic [127:0] tmpDataFromMem;
    assign tmpDataFromMem = memRequest.dataFromMem;
    // always_comb begin : RequestResponse
    //     // flopped outputs?
    //     cpuRequest.failed = FALSE;  // never fails
    //     cpuRequest.ready = FALSE;
    //     cpuRequest.dataFromCache = '0;
    //     if (cpuRequest.request && nextState == IDLE) begin
    //         cpuRequest.ready = TRUE;
    //         if (cpuRequest.isRead) begin
    //             if (isHit) begin
    //                 // assert (currentState == IDLE);
    //                 cpuRequest.dataFromCache = cacheMem[targetAddr.setIdx][targetWayIdx].data[targetAddr.offset*8+:32];
    //             end else begin
    //                 assert (currentState == REFILL_WAIT);
    //                 // NOTE: bypass
    //                 //       here, we cannot use cacheMem because it has NOT been updated yet
    //                 //       it will be visible in the next cycle, i.e. `currentState == DONE`
    //                 //       However, if we assigned the response at `DONE`, we would have 
    //                 //       wasted a cycle for the response to be visible to the CPU
    //                 $display("@%d: Bypass data from mem: 0x%h", DEBUG_tick,
    //                          tmpDataFromMem[targetAddr.offset*8+:32]);
    //                 cpuRequest.dataFromCache = tmpDataFromMem[targetAddr.offset*8+:32];
    //             end
    //         end
    //     end
    // end

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
                    $display("@%d: Bypass data from mem: 0x%h", DEBUG_tick,
                             tmpDataFromMem[targetAddr.offset*8+:32]);
                    cpuRequest.dataFromCache = tmpDataFromMem[targetAddr.offset*8+:32];
                end
            end
        end
    end

    // always_comb begin : Exception
    //     assert (cpuRequest.addr < DATA_MEM_SIZE)
    //     else
    //         $display(
    //             "Invalid memory access @%h while max size is %h",
    //             cpuRequest.addr + 15,
    //             DATA_MEM_SIZE
    //         );
    // end


endmodule
