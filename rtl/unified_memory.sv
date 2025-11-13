`timescale 1ps/1ps

module unified_memory
    import pkg_global_defs::*;
(
    request_control_interface.slave request,
    input logic clk,
    input addr_t addr,
    input logic isRead,
    input cacheline_data_t dataIn,
    output cacheline_data_t dataOut
`ifdef UNIFIED_MEMORY_EXPOSE_INTERNALS
    ,input byte_t debug_MEM[MEM_SIZE]
`endif
);
    localparam MEMORY_ACCESS_DELAY = 10;
    byte_t mem[DATA_MEM_SIZE];

`ifdef UNIFIED_MEMORY_EXPOSE_INTERNALS
    assign debug_MEM = mem;
`endif

    typedef enum logic [3:0] {
        IDLE,
        MOCK_DELAY,
        FINISHED
    } memory_state_t;

    memory_state_t currentState, nextState;
    logic [3:0] delayCountdown;

    always_comb begin
        assert (addr < DATA_MEM_SIZE)
        else $display("Invalid memory access @%h while max size is %h", addr + 15, DATA_MEM_SIZE);
        if (isRead) begin
            dataOut = {
                mem[addr+0],
                mem[addr+1],
                mem[addr+2],
                mem[addr+3],
                mem[addr+4],
                mem[addr+5],
                mem[addr+6],
                mem[addr+7],
                mem[addr+8],
                mem[addr+9],
                mem[addr+10],
                mem[addr+11],
                mem[addr+12],
                mem[addr+13],
                mem[addr+14],
                mem[addr+15]
            };
        end else begin
            dataOut = 1234567891;
        end
    end

    always_ff @(posedge clk) begin
        currentState <= nextState;
        if (currentState == IDLE && nextState == MOCK_DELAY) begin
            delayCountdown <= MEMORY_ACCESS_DELAY - 1;
        end else if (currentState == MOCK_DELAY && nextState == MOCK_DELAY) begin
            assert (delayCountdown > 0);
            delayCountdown <= delayCountdown - 1;
        end else if (currentState == MOCK_DELAY && nextState == FINISHED) begin
            mem[addr+0]  <= dataIn[0];
            mem[addr+1]  <= dataIn[1];
            mem[addr+2]  <= dataIn[2];
            mem[addr+3]  <= dataIn[3];
            mem[addr+4]  <= dataIn[4];
            mem[addr+5]  <= dataIn[5];
            mem[addr+6]  <= dataIn[6];
            mem[addr+7]  <= dataIn[7];
            mem[addr+8]  <= dataIn[8];
            mem[addr+9]  <= dataIn[9];
            mem[addr+10] <= dataIn[10];
            mem[addr+11] <= dataIn[11];
            mem[addr+12] <= dataIn[12];
            mem[addr+13] <= dataIn[13];
            mem[addr+14] <= dataIn[14];
            mem[addr+15] <= dataIn[15];
        end
    end

    always_comb begin
        case (currentState)
            IDLE: begin
                request.ready = FALSE;
                request.failed = FALSE;
                if (request.request) begin
                    nextState = MOCK_DELAY;
                end
            end
            MOCK_DELAY: begin
                if (delayCountdown == 0) begin
                    nextState = FINISHED;
                end else begin
                    nextState = MOCK_DELAY;
                end
            end
            FINISHED: begin
                request.ready  = TRUE;
                request.failed = FALSE;
                nextState = IDLE;
            end
            default assert(FALSE);
        endcase
    end

endmodule
;
