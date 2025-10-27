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
    parameter FIB_LOOP_ADDR = 'h00000020;
    parameter FIB_N_ZERO_ADDR = 'h00000038;
    parameter FIB_N_ONE_ADDR = 'h00000040;
    parameter FIB_END_ADDR = 'h00000048;
    parameter EXIT_PROGRAM_ADDR = 'h0000004c;

    parameter TEST_MEMORY = 'h00000005;

    // Create instructions and write to mem
    instruction_t inst;
    initial begin

        `BEGIN_WRITE_FILE("inst_mem.hex")
        `BEGIN_INST(0)
        // Instruction Sequence (Mapping from fibonacci_calculator.s)

        // Configuration and Initialization
        // ------------------------------------
        `MAKE_INST_2(li, S0, 11) // s0 holds N, the target Fibonacci index (e.g., N=8)

        // Handle Base Case N = 0
        `MAKE_INST_2(beqz, S0, {FIB_N_ZERO_ADDR - pc}[12:0])  // PC 1: If N=0, jump to fib_n_zero
        // Handle Base Case N = 1
        `MAKE_INST_2(li, A0, 1)  // PC 2: Load 1 into A0 temporarily for comparison
        `MAKE_INST_3(beq, S0, A0, {FIB_N_ONE_ADDR - pc}[12:0])  // PC 3: If N=1, jump to fib_n_one
        `MAKE_INST_2(
            li, A0, 0)  // PC 4: Reset A0 back to 0 (Original assembly required this for next check)

        // Initialize for N >= 2
        `MAKE_INST_2(li, S1, 0)  // F(i-2) = F0 = 0
        `MAKE_INST_2(li, S2, 1)  // F(i-1) = F1 = 1
        `MAKE_INST_2(li, T0, 2)  // Start counter 'i' at F2

        // -------------------
        // Label: fib_loop:
        `MAKE_LABEL("fib_loop")
        `MAKE_INST_3(bgt, T0, S0, {FIB_END_ADDR - pc}[12:0])  // If i > N, jump to fib_end (PC 21)

        // Calculation: F(i) = F(i-2) + F(i-1)
        `MAKE_INST_3(add, S3, S1, S2)  //  s3 = F_prev_prev + F_prev (Calculates F(i))
        `MAKE_INST_2(mv, S1, S2)  //  s1 (new F_prev_prev) = old F_prev
        `MAKE_INST_2(mv, S2, S3)  //  s2 (new F_prev) = F_current (F(i))

        // Loop Control
        `MAKE_INST_3(addi, T0, T0, 1)  // i = i + 1
        `MAKE_INST_1(j, FIB_LOOP_ADDR)  // Jump back to fib_loop

        // FIB_N_ZERO_ADDR (N=0 Handler)
        // ---------------------------------------
        `MAKE_LABEL("fib_n_zero")
        `MAKE_INST_2(li, A0, 0)  // Result F(0) = 0
        `MAKE_INST_1(j, EXIT_PROGRAM_ADDR)  // Jump to exit_program

        // FIB_N_ONE_ADDR (N=1 Handler)
        // --------------------------------------
        `MAKE_LABEL("fib_n_one")
        `MAKE_INST_2(li, A0, 1)  // Result F(1) = 1
        `MAKE_INST_1(j, EXIT_PROGRAM_ADDR)  // Jump to exit_program

        // FIB_END_ADDR (Loop Result)
        // ------------------------------------
        // Label: fib_end:
        `MAKE_LABEL("fib_end")
        `MAKE_INST_2(mv, A0, S2)  // Move final result from s2 into a0

        // EXIT_PROGRAM_ADDR
        // ---------------------------
        // Label: exit_program:
        `MAKE_LABEL("exit_program")
        `MAKE_INST_0(nop)
        // `MAKE_INST_2(li, A7, 10);  // PC 21: Syscall code for 'exit'
        // `MAKE_INST_0(ecall);  // PC 22: Execute the syscall

        // PC 25 onwards (Padding/NOPs may be needed depending on memory size)
        // ...
        `END_INST

        // `BEGIN_INST(0)
        // `MAKE_INST_2(li, S0, TEST_MEMORY);
        // `MAKE_INST_2(li, T1, 'h123);
        // // `MAKE_INST_2(li, T2, 0xC1A3);
        // `MAKE_INST_3(sw, T1, S0, 0);
        // `MAKE_INST_3(lw, T2, S0, 0);
        // `END_INST

        `END_WRITE_FILE("inst_mem.hex")
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
        $display("Fib[%d] = %d", 11, result);
        $finish;
    end


endmodule
