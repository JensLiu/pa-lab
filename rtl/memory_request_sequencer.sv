`timescale 1ns / 1ps
module memory_request_sequencer
    import pkg_global_defs::*;
(
    mem_request_if.slave  instCacheRequest,
    mem_request_if.slave  dataCacheRequest,
    mem_request_if.master memoryRequest
);
    always_comb begin : RequestWiring
        if (dataCacheRequest.request) begin
            memoryRequest.request = dataCacheRequest.request;
            memoryRequest.isRead = dataCacheRequest.isRead;
            memoryRequest.addr = dataCacheRequest.addr;
            memoryRequest.dataToMem = dataCacheRequest.dataToMem;
        end else if (instCacheRequest.request) begin
            memoryRequest.request = instCacheRequest.request;
            memoryRequest.isRead = instCacheRequest.isRead;
            memoryRequest.addr = instCacheRequest.addr;
            memoryRequest.dataToMem = instCacheRequest.dataToMem;
        end else begin
            memoryRequest.request = FALSE;
            memoryRequest.isRead = TRUE;
            memoryRequest.addr = '0;
            memoryRequest.dataToMem = '0;
        end
    end

    always_comb begin : ResultWiring
        dataCacheRequest.ready = FALSE;
        dataCacheRequest.failed = FALSE;
        dataCacheRequest.dataFromMem = '0;
        instCacheRequest.ready = FALSE;
        instCacheRequest.failed = FALSE;
        instCacheRequest.dataFromMem = '0;
        if (dataCacheRequest.request) begin
            dataCacheRequest.ready = memoryRequest.ready;
            dataCacheRequest.failed = memoryRequest.failed;
            dataCacheRequest.dataFromMem = memoryRequest.dataFromMem;
        end else if (instCacheRequest.request) begin
            instCacheRequest.ready = memoryRequest.ready;
            instCacheRequest.failed = memoryRequest.failed;
            instCacheRequest.dataFromMem = memoryRequest.dataFromMem;
        end
    end

endmodule
