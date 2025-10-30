`timescale 1ns / 1ps
`include "rtl_common.svh"

module memory_data
    import pkg_global_defs::*;
(
`ifdef DATA_MEMORY_EXPOSE_INTERNALS
    output byte_t DEBUG_mem[DATA_MEM_SIZE],
`endif
    input bool_t clk,
    input addr_t readAddr,
    input addr_t writeAddr,
    input word_t writeData,
    input mem_stlen_t writeDataLen,
    input bool_t writeEnable,
    output word_t readData
);
    byte_t mem[DATA_MEM_SIZE];

`ifdef DATA_MEMORY_EXPOSE_INTERNALS
    assign DEBUG_mem = mem;
`endif

    always_ff @(posedge clk) begin
        if (writeEnable) begin
            case (writeDataLen)
            MEM_STLEN_BYTE: mem[readAddr] <= writeData[7:0];
            MEM_STLEN_HALF: {mem[readAddr+1], mem[readAddr]} <= writeData[15:0];
            MEM_STLEN_WORD: {mem[readAddr+3], mem[readAddr+2], mem[readAddr+1], mem[readAddr]} <= writeData;
            default: assert(FALSE); // TODO: exception
            endcase
        end
    end

    assign readData = {mem[readAddr+3], mem[readAddr+2], mem[readAddr+1], mem[readAddr]};

endmodule
