interface rob_ticket_request_if;
    bool_t request;
    bool_t ready;
    word_t ticket;
    // types
    bool_t isStore;
    bool_t isWriteback;
    bool_t isBranch;
    // store
    mem_stlen_t stLen;
    word_t stData;
    // writeback
    reg_nr_t rd;
    // system instruction
    sys_inst_t sysInstType;
    csr_addr_t csrAddr;
    word_t csrData;
    // exception handling
    addr_t pc;
    // debug
    inst_info_t DEBUG_instInfo;

    modport master(
        output request,
        input ready,
        input ticket,
        output isStore,
        output isWriteback,
        output isBranch,
        output stLen,
        output stData,
        output rd,
        output sysInstType,
        output csrAddr,
        output csrData,
        output pc,
        output DEBUG_instInfo
    );
    modport slave(
        input request,
        output ready,
        output ticket,
        input isStore,
        input isWriteback,
        input isBranch,
        input stLen,
        input stData,
        input rd,
        input sysInstType,
        input csrAddr,
        input csrData,
        input pc,
        input DEBUG_instInfo
    );
endinterface
