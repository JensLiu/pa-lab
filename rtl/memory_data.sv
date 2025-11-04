`timescale 1ns / 1ps
`include "rtl_common.svh"

module memory_data
    import pkg_global_defs::*;
(
    input bool_t clk,
    input addr_t readAddr,
    input addr_t writeAddr,
    input word_t writeData,
    input mem_stlen_t writeDataLen,
    input bool_t writeEnable,
    output word_t readData
);
    byte_t mem[DATA_MEM_SIZE];

    always_ff @(posedge clk) begin
        if (writeEnable) begin
            assert (writeAddr < DATA_MEM_SIZE)
            else
                $display(
                    "Invalid memory access @%h while max size is %h", writeAddr, DATA_MEM_SIZE
                );
            case (writeDataLen)
                MEM_STLEN_BYTE: mem[writeAddr] <= writeData[7:0];
                MEM_STLEN_HALF: {mem[writeAddr+1], mem[writeAddr]} <= writeData[15:0];
                MEM_STLEN_WORD:
                {mem[writeAddr+3], mem[writeAddr+2], mem[writeAddr+1], mem[writeAddr]} <= writeData;
                default: assert (FALSE);  // TODO: exception
            endcase
        end
    end

    assign readData = {mem[readAddr+3], mem[readAddr+2], mem[readAddr+1], mem[readAddr]};

endmodule
