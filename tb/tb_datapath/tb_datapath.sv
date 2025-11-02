`timescale 1ns / 1ps

`include "datapath_testcases.sv"

// `define SINGLE_CYCLE

module tb_datapath;
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;

    // Clock generation
    logic tb_clk;
    always #5 tb_clk = ~tb_clk;

// `ifdef SINGLE_CYCLE
//     reg_t DEBUG_pc;
//     instruction_t DEBUG_inst;
//     reg_t DEBUG_regs[32];
//     byte_t DEBUG_inst_mem[INST_MEM_SIZE];
//     byte_t DEBUG_data_mem[DATA_MEM_SIZE];
//     reg_nr_t DEBUG_WB_rdIdx;
//     word_t DEBUG_WB_data;
//     bool_t DEBUG_WB_isWriteback;

//         datapath dut (
//     `ifdef DATAPATH_EXPOSE_INTERNALS
//             .DEBUG_pc(DEBUG_pc),
//             .DEBUG_inst(DEBUG_inst),
//             .DEBUG_regs(DEBUG_regs),
//             .DEBUG_WB_data(DEBUG_WB_data),
//             .DEBUG_WB_rdIdx(DEBUG_WB_rdIdx),
//             .DEBUG_WB_isWriteback(DEBUG_WB_isWriteback),
//     `ifdef INSTRUCTION_MEMORY_EXPOSE_INTERNALS
//             .DEBUG_inst_mem(DEBUG_inst_mem),
//     `endif
//     `ifdef DATA_MEMORY_EXPOSE_INTERNALS
//             .DEBUG_data_mem(DEBUG_data_mem),
//     `endif
//     `endif
//             .clk(tb_clk)
//         );
// `else
    reg_t DEBUG_regs[32];
    byte_t DEBUG_inst_mem[INST_MEM_SIZE];
    byte_t DEBUG_data_mem[DATA_MEM_SIZE];
    datapath_pipelined dut (
`ifdef DATAPATH_EXPOSE_INTERNALS
`ifdef INSTRUCTION_MEMORY_EXPOSE_INTERNALS
        .DEBUG_inst_mem(DEBUG_inst_mem),
`endif
`ifdef DATA_MEMORY_EXPOSE_INTERNALS
        .DEBUG_data_mem(DEBUG_data_mem),
`endif
`ifdef REGISTER_FILE_EXPOSE_INTERNALS
        .DEBUG_regs(DEBUG_regs),
`endif
`endif
        .clk(tb_clk)
    );
// `endif
    initial begin
        // datapath_testcases::branch_test1_codegen("inst_mem.hex");
        // datapath_testcases::fib_codegen("inst_mem.hex");
    end

    // run the simulation
    reg_t result;
    initial begin
        $dumpfile("tb_datapath.vcd");  // Sets the output file name
        $dumpvars(0, tb_datapath);  // Dumps all signals in the testbench and below
        tb_clk = 0;
        #200000;  // Run for sufficient time to complete execution
        // datapath_testcases::branch_test1_check(DEBUG_regs);
        // datapath_testcases::fib_check(DEBUG_regs);
        $finish;
    end


endmodule
