`timescale 1ns / 1ps
`include "../includes/includes.sv"

module register_file 
import pkg_global_defs::*;
(
    // debug infos
`ifdef REGISTER_FILE_EXPOSE_INTERNALS
    output reg_t debug_regs[31:0],
    // output bool_t debug_is_writing,
`endif

    input clk_t    clk,
    input reg_nr_t read_reg1,    // @decode stage
    input reg_nr_t read_reg2,    // @decode stage
    input reg_nr_t write_reg,    // @writeback stage
    input reg_t    write_data,   // @writeback stage
    input logic    write_enable, // @writeback stage

    output reg_t read_data1,  // @decode stage
    output reg_t read_data2   // @decode stage
);
    reg_t gp_regs[31:0];

    // initial begin
    //     for (int i = 0; i < 31; i++) begin
    //         gp_regs[i] = i;
    //     end
    // end

    // TODO: check range

    assign read_data1 = (write_enable && write_reg != 0 &&
                        write_reg == read_reg1) ? write_data : gp_regs[read_reg1];
    assign read_data2 = (write_enable && write_reg != 0 &&
                        write_reg == read_reg2) ? write_data : gp_regs[read_reg2];

    always_ff @(posedge clk) begin
        // flip-flop
        if (write_enable && write_reg != 0) begin  // why using `is_writing` here causes a problem?
            gp_regs[write_reg] <= write_data;
        end
    end

`ifdef REGISTER_FILE_EXPOSE_INTERNALS
    assign debug_regs = gp_regs;
    // assign debug_is_writing = write_enable && write_reg != 0;
`endif

endmodule
