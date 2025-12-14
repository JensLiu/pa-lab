interface rob_entry_update_request_if;
    bool_t request;
    word_t ticket;
    // store update
    bool_t isStore;
    addr_t stPhysAddr;
    bool_t stPhysAddrValid;
    bool_t stComplete;  // we could reuse rdDataValid
    // writeback update

endinterface
