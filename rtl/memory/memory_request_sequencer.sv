`timescale 1ns / 1ps

// `define MEMORY_REQUEST_SEQUENCER_PRINT(x) $display({$sformatf x})
`define MEMORY_REQUEST_SEQUENCER_PRINT(x)

module memory_request_sequencer
    import pkg_global_defs::*;
(
    input logic clk,
    mem_request_if.slave instCacheRequest,
    mem_request_if.slave dataCacheRequest,
    mem_request_if.master memoryRequest
);

    // NOTE: We did not use combinational logic here because of potential combinational loops.
    typedef enum logic [2:0] {
        IDLE,
        SURVING_DATA_WAIT,
        SURVING_DATA_DONE,
        SURVING_INST_WAIT,
        SURVING_INST_DONE
    } sequencer_state_t;

    sequencer_state_t currentState, nextState;

    always_ff @(posedge clk) begin : StateUpdate
        currentState <= nextState;
    end

    always_comb begin : NextStateLogic
        `MEMORY_REQUEST_SEQUENCER_PRINT(("@%d: ======== NextStateLogic run ========", DEBUG_tick));
        nextState = currentState;
        case (currentState)
            IDLE: begin
                // NOTE: Priority: Surving older instruction first
                if (dataCacheRequest.request) begin
                    nextState = SURVING_DATA_WAIT;
                    `MEMORY_REQUEST_SEQUENCER_PRINT(
                        ("@%d: decided IDLE -> SURVING_DATA_WAIT", DEBUG_tick));
                end else if (instCacheRequest.request) begin
                    nextState = SURVING_INST_WAIT;
                    `MEMORY_REQUEST_SEQUENCER_PRINT(
                        ("@%d: decided IDLE -> SURVING_INST_WAIT", DEBUG_tick));
                end else begin
                    `MEMORY_REQUEST_SEQUENCER_PRINT(("@%d: decided IDLE -> IDLE", DEBUG_tick));
                    assert (nextState == IDLE);
                end
            end
            SURVING_DATA_WAIT: begin
                if (memoryRequest.ready) begin
                    `MEMORY_REQUEST_SEQUENCER_PRINT(
                        ("@%d: decided SURVING_DATA_WAIT -> SURVING_DATA_DONE", DEBUG_tick));
                    nextState = SURVING_DATA_DONE;
                end else begin
                    `MEMORY_REQUEST_SEQUENCER_PRINT(
                        ("@%d: decided SURVING_DATA_WAIT -> SURVING_DATA_WAIT", DEBUG_tick));
                end
            end
            SURVING_INST_WAIT: begin
                if (memoryRequest.ready) begin
                    `MEMORY_REQUEST_SEQUENCER_PRINT(
                        ("@%d: decided SURVING_INST_WAIT -> SURVING_INST_DONE", DEBUG_tick));
                    nextState = SURVING_INST_DONE;
                end else begin
                    `MEMORY_REQUEST_SEQUENCER_PRINT(
                        ("@%d: decided SURVING_INST_WAIT -> SURVING_INST_WAIT", DEBUG_tick));
                end
            end
            SURVING_DATA_DONE: begin
                `MEMORY_REQUEST_SEQUENCER_PRINT(
                    ("@%d: decided SURVING_DATA_DONE -> IDLE", DEBUG_tick));
                nextState = IDLE;
            end
            SURVING_INST_DONE: begin
                `MEMORY_REQUEST_SEQUENCER_PRINT(
                    ("@%d: decided SURVING_INST_DONE -> IDLE", DEBUG_tick));
                nextState = IDLE;
            end
            default: begin
                assert (FALSE);
            end
        endcase
    end

    always_comb begin : MemoryRequestLogic
        if (currentState == SURVING_DATA_WAIT) begin
            `MEMORY_REQUEST_SEQUENCER_PRINT(("@%d: Send memory request", DEBUG_tick));
            assert (nextState == SURVING_DATA_WAIT || nextState == SURVING_DATA_DONE);
            assert (dataCacheRequest.request);
            memoryRequest.request = dataCacheRequest.request;
            memoryRequest.isRead = dataCacheRequest.isRead;
            memoryRequest.addr = dataCacheRequest.addr;
            memoryRequest.dataToMem = dataCacheRequest.dataToMem;
        end else if (currentState == SURVING_INST_WAIT) begin
            `MEMORY_REQUEST_SEQUENCER_PRINT(("@%d: Send memory request", DEBUG_tick));
            assert (nextState == SURVING_INST_WAIT || nextState == SURVING_INST_DONE);
            assert (instCacheRequest.request);
            memoryRequest.request = instCacheRequest.request;
            memoryRequest.isRead = instCacheRequest.isRead;
            memoryRequest.addr = instCacheRequest.addr;
            memoryRequest.dataToMem = instCacheRequest.dataToMem;
        end else begin
            `MEMORY_REQUEST_SEQUENCER_PRINT(("@%d: Drop memory request", DEBUG_tick));
            memoryRequest.request = FALSE;
            memoryRequest.isRead = TRUE;
            memoryRequest.addr = '0;
            memoryRequest.dataToMem = '0;
        end
    end

    cacheline_data_t dataFromMem;
    always_ff @(posedge clk) begin
        if (currentState == SURVING_DATA_WAIT) begin
            dataFromMem <= memoryRequest.dataFromMem;
        end else if (currentState == SURVING_INST_WAIT) begin
            dataFromMem <= memoryRequest.dataFromMem;
        end
    end
    always_comb begin : ResultLogic
        dataCacheRequest.ready = FALSE;
        dataCacheRequest.failed = FALSE;
        dataCacheRequest.dataFromMem = '0;
        instCacheRequest.ready = FALSE;
        instCacheRequest.failed = FALSE;
        instCacheRequest.dataFromMem = '0;
        if (currentState == SURVING_DATA_DONE) begin
            dataCacheRequest.ready = TRUE;
            dataCacheRequest.failed = FALSE;
            dataCacheRequest.dataFromMem = dataFromMem;
        end else if (currentState == SURVING_INST_DONE) begin
            instCacheRequest.ready = TRUE;
            instCacheRequest.failed = FALSE;
            instCacheRequest.dataFromMem = dataFromMem;
        end
    end

    always_comb begin : Properties
        if (currentState == IDLE) begin
            if (nextState == SURVING_DATA_WAIT) begin
                assert (dataCacheRequest.request);
            end else if (nextState == SURVING_INST_WAIT) begin
                assert (instCacheRequest.request);
                assert (!dataCacheRequest.request);
            end else begin
                assert (nextState == IDLE);
                assert (!instCacheRequest.request);
                assert (!dataCacheRequest.request);
            end
        end else if (currentState == SURVING_DATA_WAIT) begin
            assert (memoryRequest.request);
            assert (dataCacheRequest.request);
            if (nextState == SURVING_DATA_DONE) begin
                assert (memoryRequest.ready);
            end else begin
                assert (nextState == SURVING_DATA_WAIT);
                assert (!memoryRequest.ready);
            end
        end else if (currentState == SURVING_INST_WAIT) begin
            assert (memoryRequest.request);
            assert (instCacheRequest.request);
            if (nextState == SURVING_INST_DONE) begin
                assert (memoryRequest.ready);
            end else begin
                assert (nextState == SURVING_INST_WAIT);
                assert (!memoryRequest.ready);
            end
        end
    end

    logic [31:0] DEBUG_tick;
    always_ff @(posedge clk) begin
        DEBUG_tick <= DEBUG_tick + 1;
    end

endmodule
