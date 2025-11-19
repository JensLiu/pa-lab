// Copyright (c) 2025
`timescale 1ns / 1ps

module tb_unified_memory;
    import pkg_global_defs::*;

    // Clock generation
    logic clk;

    // DUT signals / interface
    mem_request_if request_if ();
    cacheline_data_t pattern1;
    cacheline_data_t pattern2;

    byte_t DEBUG_mem[MEM_SIZE];

    // Instantiate DUT
    unified_memory dut (
        .request(request_if.slave),
        .clk(clk),
`ifdef UNIFIED_MEMORY_EXPOSE_INTERNALS
        .DEBUG_mem(DEBUG_mem)
`endif
    );

    // simple clock: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // helpers
    task automatic write_cacheline(addr_t a, cacheline_data_t d);
        begin
            request_if.addr = a;
            request_if.isRead = 0;
            request_if.dataToMem = d;
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
            request_if.addr = a;
            request_if.isRead = 1;
            request_if.request = TRUE;
            @(posedge clk);

            // wait for ready
            wait (request_if.ready == TRUE);
            @(posedge clk);

            // check returned dataFromMem bytes
            for (i = 0; i < 16; i = i + 1) begin
                if (request_if.dataFromMem[i*8+:8] !== expected[i*8+:8]) begin
                    $display("[FAIL] read mismatch at addr %0h byte %0d", request_if.addr + i, i);
                    $display("  got %02x expected %02x", request_if.dataFromMem[i*8+:8],
                             expected[i*8+:8]);
                    $fatal(1);
                end
            end
            $display("[PASS] read match at addr %0h", request_if.addr);
        end
    endtask

    // test sequence
    initial begin
        // vcd
        $dumpfile("tb_unified_memory.fst");
        $dumpvars(0, tb_unified_memory);

        // initialize interface signals
        request_if.request = FALSE;
        // request_if.ready is driven by DUT, do not drive it from TB
        // request_if.failed is driven by DUT, do not drive it from TB

        request_if.addr = '0;
        request_if.isRead = 0;
        request_if.dataToMem = '{default: '0};

        // small wait for stable init
        repeat (2) @(posedge clk);

        // --- TEST 1: write then read back at addr 0
        for (int i = 0; i < 16; i++) begin
            pattern1[i*8+:8] = i[7:0];
        end

        $display("Starting TEST 1: write/read at addr 0");
        write_cacheline(0, pattern1);
        // give one cycle for memory commit
        repeat (1) @(posedge clk);
        read_cacheline_and_check(0, pattern1);

        // --- TEST 2: write at unaligned address 4 and read back
        pattern2 = {
            8'hEF,
            8'hED,
            8'hFE,
            8'h99,
            8'h88,
            8'h77,
            8'h66,
            8'h55,
            8'h44,
            8'h33,
            8'h22,
            8'h11,
            8'hDD,
            8'hCC,
            8'hBB,
            8'hAA
        };
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
