`timescale 1ns / 1ps
`include "../includes/includes.sv"

module memory_data
    import pkg_global_defs::*;
(
`ifdef DATA_MEMORY_EXPOSE_INTERNALS
    output byte_t DEBUG_mem[DATA_MEM_SIZE],
`endif
    input  bool_t clk,
    input  addr_t readAddr,
    input  addr_t writeAddr,
    input  word_t writeData,
    input  bool_t writeEnable,
    output word_t readData
);
    byte_t mem[DATA_MEM_SIZE];

`ifdef DATA_MEMORY_EXPOSE_INTERNALS
    assign DEBUG_mem = mem;
`endif

    always_ff @(posedge clk) begin
        if (writeEnable) begin
            {mem[readAddr+3], mem[readAddr+2], mem[readAddr+1], mem[readAddr]} <= writeData;
        end else begin
            readData <= {mem[readAddr+3], mem[readAddr+2], mem[readAddr+1], mem[readAddr]};
        end
    end

endmodule
