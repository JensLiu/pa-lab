interface rob_ticket_request_if;
    bool_t request;
    bool_t ready;
    word_t ticket;
    bool_t isStore;
    mem_stlen_t stLen;
    word_t stData;
    bool_t isWriteback;
    reg_nr_t rd;
    addr_t pc;
    inst_info_t DEBUG_instInfo;
    modport master(
        output request,
        input ready,
        input ticket,
        output isStore,
        output stLen,
        output stData,
        output isWriteback,
        output rd,
        output pc,
        output DEBUG_instInfo
    );
    modport slave(
        input request,
        output ready,
        output ticket,
        input isStore,
        input stLen,
        input stData,
        input isWriteback,
        input rd,
        input pc,
        input DEBUG_instInfo
    );
endinterface
