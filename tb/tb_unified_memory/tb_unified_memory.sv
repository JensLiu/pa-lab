// Copyright (c) 2025
`timescale 1ns / 1ps

module tb_unified_memory;
    import pkg_global_defs::*;

    // Clock generation
    logic clk;

    // DUT signals / interface
    request_control_interface request_if ();
    addr_t addr;
    logic isRead;
    cacheline_data_t dataIn;
    cacheline_data_t dataOut;
    cacheline_data_t pattern1;
    cacheline_data_t pattern2;

    // Instantiate DUT
    unified_memory dut (
        .request(request_if.slave),
        .clk(clk),
        .addr(addr),
        .isRead(isRead),
        .dataIn(dataIn),
        .dataOut(dataOut)
    );

    // simple clock: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // helpers
    task automatic write_cacheline(addr_t a, cacheline_data_t d);
        begin
            addr = a;
            isRead = 0;
            dataIn = d;
            request_if.request = TRUE;
            @(posedge clk);

            // wait for ready
            wait (request_if.ready == TRUE);
            @(posedge clk);  // sample after ready asserted
        end
    endtask

    task automatic read_cacheline_and_check(addr_t a, cacheline_data_t expected);
        integer i;
        begin
            addr = a;
            isRead = 1;
            request_if.request = TRUE;
            @(posedge clk);

            // wait for ready
            wait (request_if.ready == TRUE);
            @(posedge clk);

            // check returned dataOut bytes
            for (i = 0; i < 16; i = i + 1) begin
                if (dataOut[i] !== expected[15-i]) begin
                    $display("[FAIL] read mismatch at addr %0h byte %0d", addr + i, i);
                    $display("  got %02x expected %02x", dataOut[i], expected[i]);
                    $fatal(1);
                end
            end
            $display("[PASS] read match at addr %0h", addr);
        end
    endtask

    // test sequence
    initial begin
        // vcd
        $dumpfile("tb_unified_memory.vcd");
        $dumpvars(0, tb_unified_memory);

        // initialize interface signals
        request_if.request = FALSE;
        // request_if.ready is driven by DUT, do not drive it from TB
        request_if.failed = FALSE;

        addr = '0;
        isRead = 0;
        dataIn = '{default: '0};

        // small wait for stable init
        repeat (2) @(posedge clk);

        // --- TEST 1: write then read back at addr 0
        pattern1[0]  = 8'h00;
        pattern1[1]  = 8'h01;
        pattern1[2]  = 8'h02;
        pattern1[3]  = 8'h03;
        pattern1[4]  = 8'h04;
        pattern1[5]  = 8'h05;
        pattern1[6]  = 8'h06;
        pattern1[7]  = 8'h07;
        pattern1[8]  = 8'h08;
        pattern1[9]  = 8'h09;
        pattern1[10] = 8'h0A;
        pattern1[11] = 8'h0B;
        pattern1[12] = 8'h0C;
        pattern1[13] = 8'h0D;
        pattern1[14] = 8'h0E;
        pattern1[15] = 8'h0F;

        $display("Starting TEST 1: write/read at addr 0");
        write_cacheline(0, pattern1);
        // give one cycle for memory commit
        repeat (1) @(posedge clk);
        read_cacheline_and_check(0, pattern1);

        // --- TEST 2: write at unaligned address 4 and read back
        pattern2[0]  = 8'hAA;
        pattern2[1]  = 8'hBB;
        pattern2[2]  = 8'hCC;
        pattern2[3]  = 8'hDD;
        pattern2[4]  = 8'h11;
        pattern2[5]  = 8'h22;
        pattern2[6]  = 8'h33;
        pattern2[7]  = 8'h44;
        pattern2[8]  = 8'h55;
        pattern2[9]  = 8'h66;
        pattern2[10] = 8'h77;
        pattern2[11] = 8'h88;
        pattern2[12] = 8'h99;
        pattern2[13] = 8'hFE;
        pattern2[14] = 8'hED;
        pattern2[15] = 8'hEF;
        $display("Starting TEST 2: write/read at addr 4");
        write_cacheline(4, pattern2);
        repeat (1) @(posedge clk);
        read_cacheline_and_check(4, pattern2);

        // finished
        $display("All tests passed");
        #20;
        $finish;
    end

endmodule
;
