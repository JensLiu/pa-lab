`timescale 1ns / 1ps

`include "../includes/includes.sv"

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

    // --- Program Counter (PC) Address Constants ---
    parameter PC_START = 0;
    parameter FIB_LOOP_ADDR = 8;
    parameter FIB_N_ZERO_ADDR = 15;
    parameter FIB_N_ONE_ADDR = 18;
    parameter FIB_END_ADDR = 21;
    parameter EXIT_PROGRAM_ADDR = 23;

    // Create instructions and write to mem
    instruction_t inst;
    initial begin

        `BEGIN_WRITE_FILE("inst_mem.hex")
        `BEGIN_INST(0)
        // Instruction Sequence (Mapping from fibonacci_calculator.s)

        // PC 0: Configuration and Initialization
        // ------------------------------------
        `MAKE_INST_2(li, S0, 8)  // PC 0: s0 holds N, the target Fibonacci index (e.g., N=8)

        // PC 1: Handle Base Case N = 0
        `MAKE_INST_2(beqz, S0, FIB_N_ZERO_ADDR)  // PC 1: If N=0, jump to fib_n_zero (PC 15)

        // PC 2-3: Handle Base Case N = 1
        `MAKE_INST_2(li, A0, 1)  // PC 2: Load 1 into A0 temporarily for comparison
        `MAKE_INST_3(beq, S0, A0, FIB_N_ONE_ADDR)  // PC 3: If N=1, jump to fib_n_one (PC 18)
        `MAKE_INST_2(
            li, A0, 0)  // PC 4: Reset A0 back to 0 (Original assembly required this for next check)

        // PC 5-7: Initialize for N >= 2
        `MAKE_INST_2(li, S1, 0)  // PC 5: F(i-2) = F0 = 0
        `MAKE_INST_2(li, S2, 1)  // PC 6: F(i-1) = F1 = 1
        `MAKE_INST_2(li, T0, 2)  // PC 7: Start counter 'i' at F2

        // PC 8: FIB_LOOP_ADDR
        // -------------------
        // Label: fib_loop:
        // (Actual address is determined by the instructions preceding it, here PC 8)

        // PC 9: Loop Condition
        `MAKE_INST_3(bgt, T0, S0, FIB_END_ADDR)  // PC 9: If i > N, jump to fib_end (PC 21)

        // PC 10-12: Calculation: F(i) = F(i-2) + F(i-1)
        `MAKE_INST_3(add, S3, S1, S2)  // PC 10: s3 = F_prev_prev + F_prev (Calculates F(i))
        `MAKE_INST_2(mv, S1, S2)  // PC 11: s1 (new F_prev_prev) = old F_prev
        `MAKE_INST_2(mv, S2, S3)  // PC 12: s2 (new F_prev) = F_current (F(i))

        // PC 13-14: Loop Control
        `MAKE_INST_3(addi, T0, T0, 1)  // PC 13: i = i + 1
        `MAKE_INST_1(jal, FIB_LOOP_ADDR)  // PC 14: Jump back to fib_loop (PC 8)

        // PC 15-16: FIB_N_ZERO_ADDR (N=0 Handler)
        // ---------------------------------------
        // Label: fib_n_zero:
        `MAKE_INST_2(li, A0, 0)  // PC 15: Result F(0) = 0
        `MAKE_INST_1(jal, EXIT_PROGRAM_ADDR)  // PC 16: Jump to exit_program (PC 23)

        // PC 17-19: FIB_N_ONE_ADDR (N=1 Handler)
        // --------------------------------------
        // Label: fib_n_one:
        `MAKE_INST_2(li, A0, 1)  // PC 17: Result F(1) = 1
        `MAKE_INST_1(jal, EXIT_PROGRAM_ADDR)  // PC 18: Jump to exit_program (PC 23)

        // PC 20-22: FIB_END_ADDR (Loop Result)
        // ------------------------------------
        // Label: fib_end:
        `MAKE_INST_2(mv, A0, S2)  // PC 20: Move final result from s2 into a0

        // PC 23-24: EXIT_PROGRAM_ADDR
        // ---------------------------
        // Label: exit_program:
        `MAKE_INST_0(nop)
        // `MAKE_INST_2(li, A7, 10);  // PC 21: Syscall code for 'exit'
        // `MAKE_INST_0(ecall);  // PC 22: Execute the syscall

        // PC 25 onwards (Padding/NOPs may be needed depending on memory size)
        // ...
        `END_INST
        `END_WRITE_FILE("inst_mem.hex")
    end

    // run the simulation
    initial begin
        $dumpfile("tb_datapath.vcd");  // Sets the output file name
        $dumpvars(0, tb_datapath);  // Dumps all signals in the testbench and below
        tb_clk = 0;
        #2000;  // Run for sufficient time to complete execution
        $finish;
    end


endmodule
