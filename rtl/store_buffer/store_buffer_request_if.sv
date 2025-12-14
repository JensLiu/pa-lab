import pkg_global_defs::*;
interface store_buffer_request_if;
    bool_t request;
    bool_t isRead;
    bool_t isReadHit;
    bool_t isDraining;
    addr_t addr;
    word_t dataToSB;
    word_t dataFromSB;
    mem_stlen_t dataLen;

    modport master(
        output request,
        output isRead,
        input isReadHit,
        input isDraining,
        output addr,
        output dataToSB,
        input dataFromSB,
        output dataLen
    );

    modport slave(
        input request,
        input isRead,
        output isReadHit,
        output isDraining,
        input addr,
        input dataToSB,
        output dataFromSB,
        input dataLen
    );

endinterface
