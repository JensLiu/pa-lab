`timescale 1ns / 1ps
`include "rtl_common.svh"

// data line: 128-bit (16 bytes)
// # of sets: 8 -> 3-bit addressing
// # of ways: 2
// offset within the cacheline: 4-bit
//  - 128 bits within the cache line => 16 bytes => 4-bit addressing
// [tag][set][offset]
typedef struct packed {
    bool_t        valid;
    bool_t        dirty;
    logic [24:0]  tag;    // 25 bits de tag
    logic [127:0] data;   // 16 bytes = 128 bits
} cache_line_t;

typedef cache_line_t [1:0] cache_set_t;  //2 way associative

typedef cache_set_t [7:0] cache_t;  // 8 sets

typedef struct {logic lastUsed;} cache_lru_policy_t;

typedef struct packed {
    logic [31:7] tag;
    logic [6:4]  setIdx;  // 2-bit set address (8 sets)
    logic [3:0]  offset;  // 4-bit byte offset address
} addr_access_t;

module cache
    import pkg_global_defs::*;
    import pkg_riscv_instructions::*;
(
    input logic clk,
    cache_request_if.slave cpuRequest,
    mem_request_if.master memRequest
);

    typedef enum logic [3:0] {
        IDLE,
        LOOKUP,
        EVICT,
        REFILL,
        DONE
    } cache_state_t;


    cache_t cache;
    cache_lru_policy_t metainfo[8];
    cache_state_t currentState, nextState;
    word_t hitData;
    bool_t  hit;
    bool_t  isSetFull;
    logic  waySelect;
    logic  victimWayIdx;
    addr_t addr = cpuRequest.addr;

    always_ff @(posedge clk) begin
        if (cpuRequest.invalidateAll) begin
            for (int s = 0; s < 8; s++) begin
                for (int w = 0; w < 2; w++) begin
                    cache[s][w].valid <= 0;
                    cache[s][w].dirty <= 0;
                end
            end
        end
    end

    // hit detection and victim selection
    always_comb begin
        cache_set_t set = cache[addr.setIdx];
        if (set[0].tag == addr.tag && set[0].valid) begin
            metainfo[addr.setIdx].lastUsed = 0;
            hit = 0;
            waySelect = 0;
        end else if (set[1].tag == addr.tag && set[1].valid) begin
            metainfo[addr.setIdx].lastUsed = 1;
            hit = 1;
            waySelect = 1;
        end else begin
            hit = 0;
            waySelect = 0;
            victimWayIdx = ~metainfo[addr.setIdx].lastUsed;
        end
    end

    // State Register
    always_ff @(posedge clk) begin
        if (cpuRequest.reset) begin
            currentState <= IDLE;
        end else begin
            currentState <= nextState;
            if (currentState == LOOKUP && nextState == DONE) begin
                if (!cpuRequest.isRead) begin
                    cache[addr.setIdx][waySelect].data[addr.offset*8+:32] <= cpuRequest.dataToCache;
                    cache[addr.setIdx][waySelect].dirty <= 1;
                end
            end
        end
    end

    // if it's not a read request, discard this value
    assign cpuRequest.dataFromCache = set[waySelect].data[addr.offset*8+:32];
    assign memRequest.addr = cpuRequest.addr;

    // Next State Logic
    always_comb begin
        nextState = currentState;
        case (currentState)
            IDLE: begin
                if (cpuRequest.request) begin
                    nextState = LOOKUP;
                end
            end
            // TODO: IN PROGRESS
            LOOKUP: begin
                if (hit) begin
                    cache_set_t set = cache[addr.setIdx];
                    nextState = DONE;
                end else begin
                    if (isRead) begin

                    end
                end
            end
            EVICT: begin
                memRequest.request   = TRUE;
                memRequest.nextState = REFILL;
            end
            REFILL: begin
                nextState = DONE;
            end
            DONE: begin
                nextState = IDLE;
            end
            default: begin
                nextState = IDLE;
            end
        endcase
    end
endmodule
;
