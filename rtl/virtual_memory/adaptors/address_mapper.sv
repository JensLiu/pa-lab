module address_mapper
    import pkg_virtual_memory::*;
    import pkg_global_defs::*;
(
    input clk_t clk,
    // Request address translaion
    cache_request_if.slave virtualRequest,      // request w/ virtual address
    cache_request_if.master physicalRequest    // request w/ physical address
    // MMU Request
);



endmodule
