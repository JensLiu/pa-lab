`timescale 1ns / 1ps

import pkg_global_defs::*;
import pkg_riscv_instructions::*;


module cache (
    input logic clk,
    cache_request_if.slave cpuRequest,
    mem_request_if.master memRequest
);

    // data line: 128-bit (16 bytes)
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
        DONE
    } cache_state_t;

    cache_state_t currentState, nextState;

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
        isVictimDirty = FALSE;
        isSetFull = FALSE;
        isHit = FALSE;
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

    always_ff @(posedge clk) begin : PolicyUpdate
        // Only update after a successful read/write
        if (currentState == DONE) begin
            policyMetadata[targetAddr.setIdx].lastUsed <= targetWayIdx;
            // assert (cpuRequest.request);
        end
    end

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
    end

    always_comb begin : NextStateLogic
        nextState = currentState;
        case (currentState)
            IDLE: begin
                if (cpuRequest.request) begin
                    if (isHit) begin
                        nextState = DONE;
                    end else if (isSetFull && isVictimDirty) begin
                        nextState = EVICT_WAIT;
                    end else begin
                        nextState = REFILL_WAIT;
                    end
                end
            end
            EVICT_WAIT: begin
                if (memRequest.ready) begin
                    nextState = REFILL_WAIT;
                end
            end
            REFILL_WAIT: begin
                if (memRequest.ready) begin
                    nextState = DONE;
                end
            end
            DONE: begin
                nextState = IDLE;
            end
            default: begin
                assert (FALSE);
            end
        endcase
    end

    always_ff @(posedge clk) begin : MemoryRequestLogic
        memRequest.request <= FALSE;
        memRequest.isRead <= FALSE;
        memRequest.addr <= '0;
        memRequest.dataToMem <= '0;
        if (nextState == EVICT_WAIT) begin
            memRequest.request <= TRUE;
            memRequest.isRead <= FALSE;
            memRequest.addr <= victimAddr;
            memRequest.dataToMem <= victimLine;
        end else if (nextState == REFILL_WAIT) begin
            memRequest.request <= TRUE;
            memRequest.isRead <= TRUE;
            memRequest.addr <= targetAddr;
        end
    end


    always_ff @(posedge clk) begin : CacheMemoryUpdate
        if (currentState == REFILL_WAIT && nextState == DONE) begin
            cacheMem[targetAddr.setIdx][targetWayIdx].data  <= memRequest.dataFromMem;
            cacheMem[targetAddr.setIdx][targetWayIdx].tag   <= targetAddr.tag;
            cacheMem[targetAddr.setIdx][targetWayIdx].valid <= 1'b1;
            cacheMem[targetAddr.setIdx][targetWayIdx].dirty <= 1'b0;
            assert (!isHit);
        end else if (currentState == DONE && !cpuRequest.isRead) begin
            // NOTE: the written memory is only visible after `DONE` (i.e. in `IDLE`)
            //       this is fine since we did a bypass in the `RequestResponse` block
            cacheMem[targetAddr.setIdx][targetWayIdx].data[targetAddr.offset*8+:32] <= cpuRequest.dataToCache;
            cacheMem[targetAddr.setIdx][targetWayIdx].dirty <= 1'b1;
        end
    end

    // use this tmp variable to make Verilator happy
    logic [127:0] tmpDataFromMem;
    assign tmpDataFromMem = memRequest.dataFromMem;

    // TODO: for a cache hit read, we require 1 clock cycle to produce the result
    //       can we use combinational logic to make data available at the same cycle?
    always_ff @(posedge clk) begin : RequestResponse
        // flopped outputs?
        cpuRequest.failed <= FALSE;  // never fails
        cpuRequest.ready  <= nextState == DONE;
        if (nextState == DONE && cpuRequest.isRead) begin
            if (isHit) begin
                assert (currentState == IDLE);
                cpuRequest.dataFromCache <= cacheMem[targetAddr.setIdx][targetWayIdx].data[targetAddr.offset*8+:32];
            end else begin
                assert (currentState == REFILL_WAIT);
                // NOTE: bypass
                //       here, we cannot use cacheMem because it has NOT been updated yet
                //       it will be visible in the next cycle, i.e. `currentState == DONE`
                //       However, if we assigned the response at `DONE`, we would have 
                //       wasted a cycle for the response to be visible to the CPU
                cpuRequest.dataFromCache <= tmpDataFromMem[targetAddr.offset*8+:32];
            end
        end else begin
            cpuRequest.dataFromCache <= '0;
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
