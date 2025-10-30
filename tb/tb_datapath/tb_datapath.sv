`timescale 1ns / 1ps

`include "datapath_testcases.sv"

module tb_datapath;
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;

    // Clock generation
    logic tb_clk;
    always #5 tb_clk = ~tb_clk;

    reg_t DEBUG_pc;
    instruction_t DEBUG_inst;
    reg_t DEBUG_regs[32];
    byte_t DEBUG_inst_mem[INST_MEM_SIZE];
    byte_t DEBUG_data_mem[DATA_MEM_SIZE];
    reg_nr_t DEBUG_WB_rdIdx;
    word_t DEBUG_WB_data;
    bool_t DEBUG_WB_isWriteback;

    datapath dut (
`ifdef DATAPATH_EXPOSE_INTERNALS
        .DEBUG_pc(DEBUG_pc),
        .DEBUG_inst(DEBUG_inst),
        .DEBUG_regs(DEBUG_regs),
        .DEBUG_WB_data(DEBUG_WB_data),
        .DEBUG_WB_rdIdx(DEBUG_WB_rdIdx),
        .DEBUG_WB_isWriteback(DEBUG_WB_isWriteback),
`ifdef INSTRUCTION_MEMORY_EXPOSE_INTERNALS
        .DEBUG_inst_mem(DEBUG_inst_mem),
`endif
`ifdef DATA_MEMORY_EXPOSE_INTERNALS
        .DEBUG_data_mem(DEBUG_data_mem),
`endif
`endif
        .clk(tb_clk)
    );

    initial begin
        datapath_testcases::make_memtest1();
    end

    // run the simulation
    reg_t result;
    initial begin
        $dumpfile("tb_datapath.vcd");  // Sets the output file name
        $dumpvars(0, tb_datapath);  // Dumps all signals in the testbench and below
        tb_clk = 0;
        #2000;  // Run for sufficient time to complete execution
        result = DEBUG_regs[A0];
        // assert (result == 21) else $display("Failed");
        // $display("Fib[%d] = %d", 11, result);
        $finish;
    end


endmodule
