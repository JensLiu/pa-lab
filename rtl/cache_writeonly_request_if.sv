import pkg_global_defs::*;
interface cache_writeonly_request_if;

    bool_t request;
    bool_t ready;
    bool_t failed;
    addr_t addr;
    word_t dataToCache;
    mem_stlen_t dataLen;

    modport master(
        output request,
        input ready,
        output failed,
        output addr,
        output dataToCache,
        output dataLen
    );
    modport slave(
        input request,
        output ready,
        input failed,
        input addr,
        input dataToCache,
        input dataLen
    );

endinterface
