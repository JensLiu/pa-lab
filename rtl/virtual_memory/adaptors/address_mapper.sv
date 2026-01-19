module address_mapper
    import pkg_virtual_memory::*;
    import pkg_global_defs::*;
(
    input clk_t clk,
    addr_mapper_control_t mapperControl,
    // Request address translaion
    cache_request_if.slave virtualRequest,
    cache_request_if.master physicalRequest,
    // MMU Request
    cpu_mmu_if.cpu mmuRequest
);

    always_comb begin

        physicalRequest.request = FALSE;
        physicalRequest.addr = '0;
        physicalRequest.isRead = FALSE;
        physicalRequest.invalidateAll = FALSE;
        physicalRequest.dataToCache = '0;
        physicalRequest.dataLen = MEM_STLEN_INVALID;

        virtualRequest.ready = FALSE;
        virtualRequest.failed = FALSE;
        virtualRequest.dataFromCache = '0;

        mmuRequest.req = FALSE;
        mmuRequest.vaddr = '0;
        mmuRequest.access_type = ACCESS_LOAD;
        mmuRequest.satp = '0;
        mmuRequest.curr_priv_mode = USER_MODE;
        mmuRequest.mmu_enable = FALSE;
        mmuRequest.flush = FALSE;

        if (mapperControl.vmEnabled) begin
            // request MMU
            mmuRequest.req = virtualRequest.request;
            mmuRequest.vaddr = virtualRequest.addr;
            mmuRequest.access_type = virtualRequest.isRead ? ACCESS_LOAD : ACCESS_STORE;
            mmuRequest.satp = mapperControl.satp;
            mmuRequest.curr_priv_mode = mapperControl.currentPrivMode;
            mmuRequest.mmu_enable = mapperControl.vmEnabled;
            mmuRequest.flush = 1'b0;  // No TLB flush from this module

            if (mmuRequest.ready) begin
                // MMU translation ready
                if (!mmuRequest.page_fault) begin
                    physicalRequest.request = virtualRequest.request;
                    physicalRequest.addr = mmuRequest.paddr;
                    physicalRequest.isRead = virtualRequest.isRead;
                    physicalRequest.invalidateAll = virtualRequest.invalidateAll;
                    physicalRequest.dataToCache = virtualRequest.dataToCache;
                    physicalRequest.dataLen = virtualRequest.dataLen;
                    virtualRequest.ready = physicalRequest.ready;
                    virtualRequest.failed = physicalRequest.failed;
                    virtualRequest.dataFromCache = physicalRequest.dataFromCache;
                end else begin
                    virtualRequest.ready = TRUE;
                    // find out a way to distinguish between exceptions
                    virtualRequest.failed = TRUE;
                end
            end

        end else begin
            // address passthrough
            physicalRequest.request = virtualRequest.request;
            physicalRequest.addr = virtualRequest.addr;
            physicalRequest.isRead = virtualRequest.isRead;
            physicalRequest.invalidateAll = virtualRequest.invalidateAll;
            physicalRequest.dataToCache = virtualRequest.dataToCache;
            physicalRequest.dataLen = virtualRequest.dataLen;
            virtualRequest.ready = physicalRequest.ready;
            virtualRequest.failed = physicalRequest.failed;
            virtualRequest.dataFromCache = physicalRequest.dataFromCache;
        end
    end

endmodule
