interface cache_request_if;
    import pkg_global_defs::*;

    bool_t request;
    bool_t ready;
    bool_t failed;
    bool_t isRead;
    bool_t invalidateAll;
    addr_t addr;
    word_t dataToCache;
    word_t dataFromCache;

    modport master (
        output request,
        input ready,
        input failed,
        output isRead,
        output invalidateAll,
        output addr,
        output dataToCache,
        input dataFromCache
    );

    modport slave (
        input request,
        output ready,
        output failed,
        input isRead,
        input invalidateAll,
        input addr,
        input dataToCache,
        output dataFromCache
    );

endinterface;