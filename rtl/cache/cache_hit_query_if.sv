interface cache_hit_query_if;
    import pkg_global_defs::*;
    addr_t addr;
    mem_stlen_t dataLen;
    word_t dataFromCache;
    bool_t isHit;

    modport master(output addr, output dataLen, input dataFromCache, input isHit);
    modport slave(input addr, input dataLen, output dataFromCache, output isHit);

endinterface
