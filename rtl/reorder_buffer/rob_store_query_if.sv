interface rob_store_query_if;  // LOAD for bypasses (MEM)
    virt_addr_unique_t virtAddr;
    bool_t hasEntry;
    word_t data;
    // NOTE:
    // if we only write one byte to an address and want to read a whole bit from the address
    // we should first read the old one from the cache and then apply this upda te
    mem_stlen_t dataLen;
    modport master(output virtAddr, input hasEntry, input data, input dataLen);
    modport slave(input virtAddr, output hasEntry, output data, output dataLen);
endinterface
