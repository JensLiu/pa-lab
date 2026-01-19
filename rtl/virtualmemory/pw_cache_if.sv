interface pw_cache_if;
    import pkg_virtual_memory::*;
    import pkg_global_defs::*;
    // ---------------- Request ----------------
    logic           req;            // start memory access
    addr_t       addr;           // physical address
    logic           is_write;       // read or write
    logic [31:0]    wdata;          // write data
    // ---------------- Response ----------------
    logic           ready;          // response valid
    logic [31:0]    rdata;          // read data
    logic           fault;          // memory access fault

    modport page_walker (
        // output ports
        output req,
        output addr,
        output is_write,
        output wdata,
        // input ports
        input ready,
        input rdata,
        input fault
    );

    modport memory_controller (
        // input ports
        input req,
        input addr,
        input is_write,
        input wdata,
        // output ports
        output ready,
        output rdata,
        output fault
    );
endinterface : pw_cache_if