`timescale 1ns / 1ps

module tb_alu;

    // Inputs
    logic [31:0] A, B;
    logic [ 4:0] alu_op;

    // Output
    logic [31:0] y;

    // Import ALU opcodes from your package
    import pkg_global_defs::*;

    // Instantiate the ALU
    alu dut (
        .A(A),
        .B(B),
        .aluOp(alu_op),
        .Y(y)
    );

    // Test variables
    integer passed = 0, failed = 0;

    task automatic check_eq(string name, logic [31:0] actual, logic [31:0] expected);
        if (actual === expected) begin
            $display("[PASS] %s: %h == %h", name, actual, expected);
            passed++;
        end else begin
            $display("[FAIL] %s: %h != %h", name, actual, expected);
            failed++;
        end
    endtask

    initial begin
        $display("tb_alu starting");
        $dumpfile("tb_alu.vcd");
        $dumpvars(0, tb_alu);

        // Test ADD
        A = 32'h0000_0001;
        B = 32'h0000_0002;
        alu_op = ALU_ADD;
        #1;
        check_eq("ADD", y, 32'h0000_0003);

        // Test SUB
        A = 32'h0000_0005;
        B = 32'h0000_0003;
        alu_op = ALU_SUB;
        #1;
        check_eq("SUB", y, 32'h0000_0002);

        // Test INC
        A = 32'h0000_0007;
        B = 32'h0000_0000;
        alu_op = ALU_INC;
        #1;
        check_eq("INC", y, 32'h0000_0008);

        // Test DEC
        A = 32'h0000_0007;
        B = 32'h0000_0000;
        alu_op = ALU_DEC;
        #1;
        check_eq("DEC", y, 32'h0000_0006);

        // Test NOT
        A = 32'hFFFF_FFFF;
        B = 32'h0000_0000;
        alu_op = ALU_NOT;
        #1;
        check_eq("NOT", y, 32'h0000_0000);

        // Test AND
        A = 32'hF0F0_F0F0;
        B = 32'h0F0F_0F0F;
        alu_op = ALU_AND;
        #1;
        check_eq("AND", y, 32'h0000_0000);

        // Test OR
        A = 32'hF0F0_F0F0;
        B = 32'h0F0F_0F0F;
        alu_op = ALU_OR;
        #1;
        check_eq("OR", y, 32'hFFFF_FFFF);

        // Test XOR
        A = 32'hAAAA_AAAA;
        B = 32'h5555_5555;
        alu_op = ALU_XOR;
        #1;
        check_eq("XOR", y, 32'hFFFF_FFFF);

        // Test SLL (logical left shift)
        A = 32'h0000_0001;
        B = 32'h0000_0004;
        alu_op = ALU_SLL;
        #1;
        // You may need to adjust expected value based on your SLL implementation
        check_eq("SLL", y, 32'h0000_0010);

        // Test SLT (signed less than)
        A = 32'hFFFF_FFFF;
        B = 32'h0000_0001;
        alu_op = ALU_SLT;
        #1;
        check_eq("SLT", y, 32'hFFFF_FFFF);

        // Test SLTU (unsigned less than)
        A = 32'h0000_0001;
        B = 32'hFFFF_FFFF;
        alu_op = ALU_SLTU;
        #1;
        check_eq("SLTU", y, 32'h0000_0001);

        // Test SRL (logical right shift)
        A = 32'h8000_0000;
        B = 32'h0000_0001;
        alu_op = ALU_SRL;
        #1;
        // You may need to adjust expected value based on your SRL implementation
        check_eq("SRL", y, 32'h4000_0000);

        // Test SRA (arithmetic right shift)
        A = 32'h8000_0000;
        B = 32'h0000_0001;
        alu_op = ALU_SRA;
        #1;
        // You may need to adjust expected value based on your SRA implementation
        check_eq("SRA", y, 32'hC000_0000);

        // Test default
        alu_op = 5'hF;
        #1;
        check_eq("DEFAULT", y, IMM_32_WHATEVER);

        $display("tb_alu done: passed=%0d failed=%0d", passed, failed);
        if (failed == 0) $display("ALL TESTS PASSED");
        else $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
