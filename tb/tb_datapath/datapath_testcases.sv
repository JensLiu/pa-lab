`timescale 1ns / 1ps

`include "tb_includes.sv"

package datapath_testcases;
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;

    function automatic void fib_codegen(string filename);
        // --- Program Counter (PC) Address Constants ---
        parameter FIB_LOOP_ADDR = 'h00000020;
        parameter FIB_N_ZERO_ADDR = 'h00000038;
        parameter FIB_N_ONE_ADDR = 'h00000040;
        parameter FIB_END_ADDR = 'h00000048;
        parameter EXIT_PROGRAM_ADDR = 'h0000004c;

        parameter TEST_MEMORY = 'h00000005;

        instruction_t inst;

        `BEGIN_WRITE_FILE(filename)
        `BEGIN_INST(0)
        // Instruction Sequence (Mapping from fibonacci_calculator.s)

        // Configuration and Initialization
        // ------------------------------------
        `MAKE_INST_2(li, S0, 11)  // s0 holds N, the target Fibonacci index (e.g., N=8)

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

        `END_WRITE_FILE(filename)
    endfunction

    function automatic void fib_check(reg_t regs[32]);
        assert (regs[A0] == 'd89)
        else $display("testcase fib failed");
    endfunction

    function automatic void memtest1_codegen(string filename);

        parameter TEST_MEMORY = 'h00000005;

        instruction_t inst;

        `BEGIN_WRITE_FILE(filename)
        `BEGIN_INST(0)
        `MAKE_INST_2(li, S0, TEST_MEMORY);
        `MAKE_INST_2(lui, T1, 'hFFFF1);
        `MAKE_INST_3(ori, T1, T1, 'h234);
        `MAKE_INST_3(sw, T1, S0, 0);
        `MAKE_INST_3(sh, T1, S0, 4);
        `MAKE_INST_3(sb, T1, S0, 6);

        `MAKE_INST_3(lw, T2, S0, 0);
        `MAKE_INST_3(lh, T3, S0, 4);
        `MAKE_INST_3(lb, T4, S0, 6);
        `END_INST
        `END_WRITE_FILE(filename)
    endfunction

    function automatic void memtest1_check(reg_t regs[32]);
        assert (regs[T2] == 'hFFFF1234)
        else $display("memtest1 failed");
        assert (regs[T3] == 'h1234)
        else $display("memtest1 failed");
        assert (regs[T4] == 'h34)
        else $display("memtest1 failed");
    endfunction

    function automatic void dependency_test1_codegen(string filename);
        instruction_t inst;
        `BEGIN_WRITE_FILE(filename)
        `BEGIN_INST(0)

        `MAKE_INST_2(li, T2, 'h123);
        `MAKE_INST_2(li, T3, 'h234);
        `MAKE_INST_3(add, T1, T2, T3);
        `MAKE_INST_3(add, T1, T1, T1);

        `END_INST
        `END_WRITE_FILE(filename)
    endfunction

    function automatic void dependency_test1_check(reg_t regs[32]);
        assert (regs[T1] == 'h6ae)
        else $display("ERROR: dependency test1 failed");
    endfunction

    function automatic void dependency_test2_codegen(string filename);
        instruction_t inst;
        `BEGIN_WRITE_FILE(filename)
        `BEGIN_INST(0)

        `MAKE_INST_2(li, T1, 'h1);  // 1
        `MAKE_INST_3(add, T1, T1, T1);  // 2
        `MAKE_INST_3(add, T1, T1, T1);  // 4
        `MAKE_INST_3(add, T1, T1, T1);  // 8
        `MAKE_INST_3(add, T1, T1, T1);  // 16
        `MAKE_INST_3(add, T1, T1, T1);  // 32
        `MAKE_INST_3(add, T1, T1, T1);  // 64
        `MAKE_INST_3(add, T1, T1, T1);  // 128
        `MAKE_INST_3(add, T1, T1, T1);  // 256
        `MAKE_INST_3(add, T1, T1, T1);  // 512

        `END_INST
        `END_WRITE_FILE(filename)
    endfunction

    function automatic void dependency_test2_check(reg_t regs[32]);
        assert (regs[T1] == 512)
        else $display("ERROR: dependency test2 failed");
    endfunction

    function automatic void dependency_test_load1_codegen(string filename);
        parameter TEST_MEMORY = 'h00000005;
        instruction_t inst;
        `BEGIN_WRITE_FILE(filename)
        `BEGIN_INST(0)
        // store value
        `MAKE_INST_2(li, S0, TEST_MEMORY);
        `MAKE_INST_2(li, T1, 'd123);
        `MAKE_INST_3(sw, T1, S0, 0);
        // create dependency
        `MAKE_INST_2(li, T1, 'd1);  // T1 = 1
        `MAKE_INST_3(lw, T2, S0, 0);  // T2 = 123
        // should halt 1 cycle for T2 (load)
        `MAKE_INST_3(add, T1, T1, T2);  // T1 = 124

        `END_INST
        `END_WRITE_FILE(filename)

    endfunction

    function automatic void dependency_test_load1_check(reg_t regs[32]);
        assert (regs[T1] == 124)
        else $display("ERROR: dependency test load1 failed");
    endfunction

    function automatic void dependency_test_load2_codegen(string filename);
        parameter TEST_MEMORY = 'h00000005;
        instruction_t inst;
        `BEGIN_WRITE_FILE(filename)
        `BEGIN_INST(0)
        // store value
        `MAKE_INST_2(li, S0, TEST_MEMORY);
        `MAKE_INST_2(li, T1, 'd123);
        `MAKE_INST_2(li, T2, 'd234);
        `MAKE_INST_3(sw, T1, S0, 0);
        `MAKE_INST_3(sw, T2, S0, 4);
        // create dependency
        `MAKE_INST_2(li, T1, 'd345);  // T1 = 345
        `MAKE_INST_2(li, T2, 'd456);  // T2 = 456
        `MAKE_INST_3(lw, T1, S0, 4);  // T1 = 234
        `MAKE_INST_3(lw, T2, S0, 0);  // T2 = 123
        // should halt 1 cycle for T2 (load)
        `MAKE_INST_3(add, T1, T1, T2);  // T1 = 357

        `END_INST
        `END_WRITE_FILE(filename)

    endfunction

    function automatic void dependency_test_load2_check(reg_t regs[32]);
        assert (regs[T1] == 357 && regs[T2] == 123)
        else $display("ERROR: dependency test load2 failed");
    endfunction

    function automatic void branch_test1_codegen(string filename);
        instruction_t inst;
        parameter N_ITERS = 10;
        parameter LOOP_ADDR = 'hc;
        parameter LOOP_EXIT_ADDR = 'h1c;
        `BEGIN_WRITE_FILE(filename)
        `BEGIN_INST(0)
        `MAKE_INST_2(li, T0, 1)  // x <- 1
        `MAKE_INST_2(li, S0, 0)  // i <- 0
        `MAKE_INST_2(li, S1, N_ITERS)   // N_ITERS
        `MAKE_LABEL("loop")
        `MAKE_INST_3(bge, S0, S1, {LOOP_EXIT_ADDR - pc}[12:0])  // if i >= 10: goto loop-exit
        `MAKE_INST_3(add, T0, T0, T0)  // x <- x + x
        `MAKE_INST_3(addi, S0, S0, 1)  // i <- i + 1
        `MAKE_INST_1(j, LOOP_ADDR)  // jmp loop
        `MAKE_LABEL("loop-exit")
        `MAKE_INST_3(addi, T0, T0, 1)  // x <- x + 1

        `END_INST
        `END_WRITE_FILE(filename)
    endfunction

    function automatic void branch_test1_check(reg_t regs[32]);
        assert (regs[S0] == 10 && regs[T0] == 1025)
        else $display("ERROR: dependency test load2 failed");
    endfunction


endpackage
;
