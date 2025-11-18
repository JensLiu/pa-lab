`timescale 1ns / 1ps
`include "rtl_common.svh"

module memory_data
    import pkg_global_defs::*;
(
    input logic clk,
    cache_request_if.slave cpuRequest
);

    byte_t mem[DATA_MEM_SIZE];

    always_ff @(posedge clk) begin
        if (cpuRequest.request && !cpuRequest.isRead) begin
            assert (cpuRequest.addr < DATA_MEM_SIZE)
            else
                $display(
                    "Invalid memory access @%h while max size is %h", cpuRequest.addr, DATA_MEM_SIZE
                );
            case (cpuRequest.dataLen)
                MEM_STLEN_BYTE: mem[cpuRequest.addr] <= cpuRequest.dataToCache[7:0];
                MEM_STLEN_HALF:
                {mem[cpuRequest.addr+1], mem[cpuRequest.addr]} <= cpuRequest.dataToCache[15:0];
                MEM_STLEN_WORD:
                {mem[cpuRequest.addr+3], mem[cpuRequest.addr+2], mem[cpuRequest.addr+1], mem[cpuRequest.addr]} <= cpuRequest.dataToCache;
                default: assert (FALSE);  // TODO: exception
            endcase
        end
    end

    assign cpuRequest.ready = TRUE;
    assign cpuRequest.dataFromCache = !cpuRequest.isRead ? 0
                        : {mem[cpuRequest.addr+3], mem[cpuRequest.addr+2], mem[cpuRequest.addr+1], mem[cpuRequest.addr]};

endmodule
