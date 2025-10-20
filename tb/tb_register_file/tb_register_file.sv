`timescale 1ns / 1ps

module tb_register_file;
    // Inputs
    logic clk;
    logic [4:0] read_reg1, read_reg2, write_reg;
    logic [31:0] write_data;
    logic write_enable;

    // Outputs
    logic [31:0] read_data1, read_data2;
    // DUT debug outputs
    logic [31:0] debug_regs[31:0];
    logic is_writing;


    // DUT
    register_file dut (
`ifdef REGISTER_FILE_EXPOSE_INTERNALS
        .debug_regs(debug_regs),
        // .debug_is_writing(is_writing)
`endif
        .clk(clk),
        .read_reg1(read_reg1),
        .read_reg2(read_reg2),
        .write_reg(write_reg),
        .write_data(write_data),
        .write_enable(write_enable),
        .read_data1(read_data1),
        .read_data2(read_data2)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

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
        $display("tb_register_file starting");
        $dumpfile("tb_register_file.vcd");  // Sets the output file name
        $dumpvars(0, tb_register_file);  // Dumps all signals in the testbench and below

        @(posedge clk);
        $display("Initial read tests");

        // 1. Write to reg 5, read back
        write_enable = 1;
        write_reg = 5;
        write_data = 32'hDEADBEEF;
        read_reg1 = 5;
        read_reg2 = 0;
        @(posedge clk);
        write_enable = 0;
        @(posedge clk);
        check_eq("Write/read reg5", read_data1, 32'hDEADBEEF);

        // 2. Write to reg 0 (should not change, if implemented as x0 always zero)
        write_enable = 1;
        write_reg = 0;
        write_data = 32'hFFFFFFFF;
        read_reg1 = 0;
        @(posedge clk);
        write_enable = 0;
        @(posedge clk);
        check_eq("Write/read reg0", read_data1, 32'd0);  // If x0 is hardwired, expect 0

        // 3. Simultaneous write and read to same reg (bypass test)
        write_enable = 1;
        write_reg = 10;
        write_data = 32'h12345678;
        read_reg1 = 10;
        @(posedge clk);
        write_enable = 0;
        @(posedge clk);
        check_eq("Bypass write/read reg10", read_data1, 32'h12345678);

        // 4. Simultaneous write to reg1, read reg2 (should not affect reg2)
        write_enable = 1;
        write_reg = 1;
        write_data = 32'hCAFEBABE;
        read_reg1 = 2;
        @(posedge clk);
        write_enable = 0;
        @(posedge clk);
        check_eq("Write reg1/read reg2", read_data1, 32'd0);

        // 5. Write to reg31, read back
        write_enable = 1;
        write_reg = 31;
        write_data = 32'hA5A5A5A5;
        read_reg1 = 31;
        @(posedge clk);
        write_enable = 0;
        @(posedge clk);
        check_eq("Write/read reg31", read_data1, 32'hA5A5A5A5);

        // 6. Data race: write to reg15, read reg15 and reg15 simultaneously
        write_enable = 1;
        write_reg = 15;
        write_data = 32'hFACEFACE;
        read_reg1 = 15;
        read_reg2 = 15;
        @(posedge clk);
        write_enable = 0;
        @(posedge clk);
        check_eq("Race write/read reg15 (1)", read_data1, 32'hFACEFACE);
        check_eq("Race write/read reg15 (2)", read_data2, 32'hFACEFACE);

        // 7. Data race: write to reg20, read reg20 and reg5 simultaneously
        write_enable = 1;
        write_reg = 20;
        write_data = 32'hBEEFBEEF;
        read_reg1 = 20;
        read_reg2 = 5;
        @(posedge clk);
        write_enable = 0;
        @(posedge clk);
        check_eq("Race write/read reg20", read_data1, 32'hBEEFBEEF);
        check_eq("Read reg5 after reg20 write", read_data2, 32'hDEADBEEF);

        // 8. Write to reg7, then overwrite with new value
        write_enable = 1;
        write_reg = 7;
        write_data = 32'h11111111;
        read_reg1 = 7;
        @(posedge clk);
        write_enable = 1;
        write_data   = 32'h22222222;
        @(posedge clk);
        write_enable = 0;
        @(posedge clk);
        check_eq("Overwrite reg7", read_data1, 32'h22222222);

        // 9. Read from unwritten reg (should be 0)
        read_reg1 = 12;
        @(posedge clk);
        check_eq("Read unwritten reg12", read_data1, 32'd0);

        // 10. Write to reg30, read reg30 and reg31
        write_enable = 1;
        write_reg = 30;
        write_data = 32'hFEEDFACE;
        read_reg1 = 30;
        read_reg2 = 31;
        @(posedge clk);
        write_enable = 0;
        @(posedge clk);
        check_eq("Write/read reg30", read_data1, 32'hFEEDFACE);
        check_eq("Read reg31 after reg30 write", read_data2, 32'hA5A5A5A5);

        // Summary
        $display("tb_register_file done: passed=%0d failed=%0d", passed, failed);
        if (failed == 0) $display("ALL TESTS PASSED");
        else $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
