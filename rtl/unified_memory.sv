`timescale 1ps/1ps

module unified_memory
    import pkg_global_defs::*;
(
    input logic clk,
    mem_request_if.slave request
`ifdef UNIFIED_MEMORY_EXPOSE_INTERNALS
    ,output byte_t DEBUG_mem[MEM_SIZE]
`endif
);
    localparam MEMORY_ACCESS_DELAY = 3;
    byte_t mem[DATA_MEM_SIZE];

    initial begin
        $display("INST_MEM_SIZE=%d", INST_MEM_SIZE);
        $readmemh("memory.hex", mem);
    end

`ifdef UNIFIED_MEMORY_EXPOSE_INTERNALS
    assign DEBUG_mem = mem;
`endif

    typedef enum logic [1:0] {
        IDLE,
        MOCK_DELAY,
        DONE
    } memory_state_t;

    memory_state_t currentState, nextState;
    logic [3:0] delayCountdown;
    logic [31:0] DEBUG_tick;

    always_comb begin : DataResponse
        if (request.request) begin
        assert (request.addr < DATA_MEM_SIZE)
        else $display("Invalid memory access @%h while max size is %h", request.addr + 15, DATA_MEM_SIZE);
        end
    end

    always_ff @(posedge clk) begin : StateUpdate
        currentState <= nextState;
        DEBUG_tick <= DEBUG_tick + 1;
    end

    always_comb begin : NextStateLogic
        nextState = currentState;
        case (currentState)
            IDLE: begin
                if (request.request) begin
                    nextState = MOCK_DELAY;
                end
            end
            MOCK_DELAY: begin
                assert (request.request);
                if (delayCountdown == 0) begin
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

    always_ff @(posedge clk) begin : CounterUpdate
        if (currentState == IDLE && nextState == MOCK_DELAY) begin
            delayCountdown <= MEMORY_ACCESS_DELAY - 1;
        end else if (currentState == MOCK_DELAY) begin
            if (delayCountdown > 0) begin
                delayCountdown <= delayCountdown - 1;
            end
        end
        assert (delayCountdown < MEMORY_ACCESS_DELAY);
    end

    always_ff @(posedge clk) begin : RequestResponse
        request.failed <= FALSE;
        request.ready <= FALSE;
        request.dataFromMem <= '0;
        if (nextState == DONE) begin
            // visible at `DONE`
            request.ready <= TRUE;
            if (request.isRead) begin
                for (int  i = 0; i < 16; i++) begin
                    // $display("@%d: [Memory]: read data @%h -> %h", DEBUG_tick,
                    //         request.addr + i, 
                    //          mem[request.addr + i]);
                    request.dataFromMem[i*8+:8] <= mem[request.addr + i];
                end
            end
        end
    end

    always_ff @(posedge clk) begin : UpdateMemory
        if (currentState == MOCK_DELAY && nextState == DONE && !request.isRead) begin
            // visible at `DONE`. It's fine since we serve one read/write request at a time
            for (int i = 0; i < 16; i++) begin
                // $display("@%d: [Memory]: write data @%h <- %h", DEBUG_tick,
                //         request.addr + i, 
                //          request.dataToMem[i*8+:8]);
                mem[request.addr + i] <= request.dataToMem[i*8+:8];
            end
        end
    end

endmodule