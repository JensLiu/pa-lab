interface mem_request_if;
    import pkg_global_defs::*;

    logic request;
    logic ready;
    logic failed;
    logic isRead;
    addr_t addr;
    cacheline_data_t dataToMem;
    cacheline_data_t dataFromMem;

    modport master(
        output request,
        input ready,
        input failed,
        output isRead,
        output addr,
        output dataToMem,
        input dataFromMem
    );

    modport slave(
        input request,
        output ready,
        output failed,
        input isRead,
        input addr,
        input dataToMem,
        output dataFromMem
    );

endinterface
;
