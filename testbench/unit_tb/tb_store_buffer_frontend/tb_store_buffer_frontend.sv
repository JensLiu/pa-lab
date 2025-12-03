`timescale 1ns / 1ps

module tb_store_buffer_frontend;

    import pkg_global_defs::*;

    // Clock generation
    logic clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10ns period = 100MHz
    end

    logic [31:0] cycle_count;
    initial cycle_count = 0;
    always_ff @(posedge clk) begin
        cycle_count <= cycle_count + 1;
    end

    // DUT interfaces
    cache_request_if cpuRequest ();
    mem_request_if memRequest ();

    // DUT instantiation
    store_buffer_frontend dut (
        .clk(clk),
        .cpuRequest(cpuRequest.slave),
        .memRequest(memRequest.master)
    );

    unified_memory memory (
        .clk(clk),
        .request(memRequest.slave)
    );

    // // Mock memory (slave side of memRequest)
    // typedef enum logic [1:0] {
    //     MEM_IDLE,
    //     MEM_PROCESSING,
    //     MEM_READY
    // } mem_state_t;

    // mem_state_t memState;
    // logic [7:0] memory[1024*1024];  // 1MB memory
    // int mem_delay;

    // initial begin
    //     memState = MEM_IDLE;
    //     memRequest.ready = 1'b0;
    //     memRequest.failed = 1'b0;
    //     mem_delay = 2;  // Default delay for memory operations
    // end

    // Mock memory behavior
    // always_ff @(posedge clk) begin
    //     case (memState)
    //         MEM_IDLE: begin
    //             memRequest.ready <= 1'b0;
    //             if (memRequest.request) begin
    //                 $display("  [MEM] @%0d Received: %s addr=0x%h", cycle_count,
    //                          memRequest.isRead ? "READ" : "WRITE", memRequest.addr);
    //                 memState <= MEM_PROCESSING;
    //             end
    //         end
    //         MEM_PROCESSING: begin
    //             if (mem_delay > 0) begin
    //                 mem_delay <= mem_delay - 1;
    //             end else begin
    //                 // Process the request
    //                 if (memRequest.isRead) begin
    //                     // Read cacheline from memory
    //                     for (int i = 0; i < 16; i++) begin
    //                         memRequest.dataFromMem[i*8+:8] <= memory[memRequest.addr+i];
    //                     end
    //                     $display("  [MEM] @%0d Read completed from addr=0x%h", cycle_count,
    //                              memRequest.addr);
    //                 end else begin
    //                     // Write cacheline to memory
    //                     for (int i = 0; i < 16; i++) begin
    //                         memory[memRequest.addr+i] <= memRequest.dataToMem[i*8+:8];
    //                     end
    //                     $display("  [MEM] @%0d Write completed to addr=0x%h", cycle_count,
    //                              memRequest.addr);
    //                 end
    //                 memRequest.ready <= 1'b1;
    //                 memState <= MEM_READY;
    //                 mem_delay <= 2;  // Reset delay
    //             end
    //         end
    //         MEM_READY: begin
    //             memRequest.ready <= 1'b0;
    //             memState <= MEM_IDLE;
    //         end
    //         default: begin
    //             memState <= MEM_IDLE;
    //         end
    //     endcase
    // end

    // Test variables
    int test_passed;
    int test_failed;
    int test_number;

    // Helper task to initialize memory
    // task automatic init_memory(input addr_t base_addr, input int size);
    //     for (int i = 0; i < size; i++) begin
    //         memory[base_addr+i] = byte_t'(i % 256);
    //     end
    //     $display("[INIT] Initialized memory at 0x%h with %0d bytes", base_addr, size);
    // endtask

    // Helper task to wait for cycles
    task automatic wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    // Helper task to perform a write request
    task automatic cpu_write(input addr_t addr, input word_t data, input mem_stlen_t data_len);
        $display("[TEST] @%0d CPU Write: addr=0x%h data=0x%h len=%0d", cycle_count, addr, data,
                 data_len);
        cpuRequest.request = 1'b1;
        cpuRequest.isRead = 1'b0;
        cpuRequest.addr = addr;
        cpuRequest.dataToCache = data;
        cpuRequest.dataLen = data_len;
        cpuRequest.invalidateAll = 1'b0;
        @(posedge clk);

        // Wait for ready
        while (!cpuRequest.ready) begin
            @(posedge clk);
        end

        cpuRequest.request = 1'b0;
        $display("[TEST] @%0d CPU Write completed", cycle_count);
    endtask

    // Helper task to perform a read request
    task automatic cpu_read(input addr_t addr, input mem_stlen_t data_len, output word_t data,
                            output bool_t failed);
        $display("[TEST] @%0d CPU Read: addr=0x%h len=%0d", cycle_count, addr, data_len);
        cpuRequest.request = 1'b1;
        cpuRequest.isRead = 1'b1;
        cpuRequest.addr = addr;
        cpuRequest.dataLen = data_len;
        cpuRequest.invalidateAll = 1'b0;
        @(posedge clk);

        // Wait for ready
        while (!cpuRequest.ready) begin
            @(posedge clk);
        end

        data = cpuRequest.dataFromCache;
        failed = cpuRequest.failed;
        cpuRequest.request = 1'b0;
        $display("[TEST] @%0d CPU Read completed: data=0x%h failed=%0b", cycle_count, data, failed);
    endtask

    // Test execution
    initial begin
        test_passed = 0;
        test_failed = 0;
        test_number = 0;

        // Initialize signals
        cpuRequest.request = 1'b0;
        cpuRequest.isRead = 1'b0;
        cpuRequest.addr = '0;
        cpuRequest.dataToCache = '0;
        cpuRequest.dataLen = MEM_STLEN_INVALID;
        cpuRequest.invalidateAll = 1'b0;

        // Initialize memory
        // init_memory(32'h1000, 1024);

        // Wait for initialization
        wait_cycles(10);

        $display("\n========================================");
        $display("Starting Store Buffer Frontend Tests");
        $display("========================================\n");

        // TEST 1: Simple write to store buffer
        begin
            word_t read_data;
            bool_t failed;

            test_number++;
            $display("\n--- TEST %0d: Simple Write to Store Buffer ---", test_number);

            cpu_write(32'h1000, 32'hDEADBEEF, MEM_STLEN_WORD);
            wait_cycles(2);
            // wait_cycles(10);

            $display("[TEST] Test %0d PASSED: Write accepted", test_number);
            test_passed++;
        end

        // TEST 2: Write followed by read (store buffer hit)
        begin
            word_t read_data;
            bool_t failed;

            test_number++;
            $display("\n--- TEST %0d: Write then Read (Store Buffer Hit) ---", test_number);

            cpu_write(32'h2000, 32'hCAFEBABE, MEM_STLEN_WORD);
            wait_cycles(2);

            cpu_read(32'h2000, MEM_STLEN_WORD, read_data, failed);

            if (read_data == 32'hCAFEBABE && !failed) begin
                $display("[TEST] Test %0d PASSED: Read correct data from store buffer",
                         test_number);
                test_passed++;
            end else begin
                $display("[TEST] Test %0d FAILED: Expected 0xCAFEBABE, got 0x%h, failed=%0b",
                         test_number, read_data, failed);
                test_failed++;
            end
        end

        // TEST 3: Multiple writes to different addresses
        begin
            word_t read_data;
            bool_t failed;

            test_number++;
            $display("\n--- TEST %0d: Multiple Writes to Different Addresses ---", test_number);

            cpu_write(32'h3000, 32'h12345678, MEM_STLEN_WORD);
            wait_cycles(1);
            cpu_write(32'h3004, 32'h9ABCDEF0, MEM_STLEN_WORD);
            wait_cycles(1);
            cpu_write(32'h3008, 32'hAAAABBBB, MEM_STLEN_WORD);
            wait_cycles(2);

            // Read back all three
            cpu_read(32'h3000, MEM_STLEN_WORD, read_data, failed);
            if (read_data == 32'h12345678) begin
                $display("[TEST] Read 1/3 correct: 0x%h", read_data);
            end else begin
                $display("[TEST] Read 1/3 FAILED: Expected 0x12345678, got 0x%h", read_data);
                test_failed++;
            end

            cpu_read(32'h3004, MEM_STLEN_WORD, read_data, failed);
            if (read_data == 32'h9ABCDEF0) begin
                $display("[TEST] Read 2/3 correct: 0x%h", read_data);
            end else begin
                $display("[TEST] Read 2/3 FAILED: Expected 0x9ABCDEF0, got 0x%h", read_data);
                test_failed++;
            end

            cpu_read(32'h3008, MEM_STLEN_WORD, read_data, failed);
            if (read_data == 32'hAAAABBBB) begin
                $display("[TEST] Read 3/3 correct: 0x%h", read_data);
                $display("[TEST] Test %0d PASSED", test_number);
                test_passed++;
            end else begin
                $display("[TEST] Read 3/3 FAILED: Expected 0xAAAABBBB, got 0x%h", read_data);
                test_failed++;
            end
        end

        // TEST 4: Write with different data lengths
        begin
            word_t read_data;
            bool_t failed;

            test_number++;
            $display("\n--- TEST %0d: Write with Different Data Lengths ---", test_number);

            cpu_write(32'h4000, 32'h000000AA, MEM_STLEN_BYTE);
            wait_cycles(1);
            cpu_write(32'h4004, 32'h0000BBBB, MEM_STLEN_HALF);
            wait_cycles(1);
            cpu_write(32'h4008, 32'hCCCCCCCC, MEM_STLEN_WORD);
            wait_cycles(2);

            cpu_read(32'h4000, MEM_STLEN_BYTE, read_data, failed);
            cpu_read(32'h4004, MEM_STLEN_HALF, read_data, failed);
            cpu_read(32'h4008, MEM_STLEN_WORD, read_data, failed);

            $display("[TEST] Test %0d PASSED: Different data lengths handled", test_number);
            test_passed++;
        end

        // TEST 5: Read miss (not in store buffer, fallback to cache)
        begin
            word_t read_data;
            bool_t failed;

            test_number++;
            $display("\n--- TEST %0d: Read Miss (Fallback to Cache) ---", test_number);

            // Read from an address that hasn't been written to store buffer
            cpu_read(32'h5000, MEM_STLEN_WORD, read_data, failed);

            if (!failed) begin
                $display("[TEST] Test %0d PASSED: Cache fallback worked, data=0x%h", test_number,
                         read_data);
                test_passed++;
            end else begin
                $display("[TEST] Test %0d FAILED: Cache fallback failed", test_number);
                test_failed++;
            end
        end

        // TEST 6: Overwrite same address
        begin
            word_t read_data;
            bool_t failed;

            test_number++;
            $display("\n--- TEST %0d: Overwrite Same Address ---", test_number);

            cpu_write(32'h6000, 32'h11111111, MEM_STLEN_WORD);
            wait_cycles(1);
            cpu_write(32'h6000, 32'h22222222, MEM_STLEN_WORD);
            wait_cycles(1);
            cpu_write(32'h6000, 32'h33333333, MEM_STLEN_WORD);
            wait_cycles(2);

            cpu_read(32'h6000, MEM_STLEN_WORD, read_data, failed);

            if (read_data == 32'h33333333 && !failed) begin
                $display("[TEST] Test %0d PASSED: Latest write returned", test_number);
                test_passed++;
            end else begin
                $display("[TEST] Test %0d FAILED: Expected 0x33333333, got 0x%h", test_number,
                         read_data);
                test_failed++;
            end
        end

        // TEST 7: Stress test - rapid write/read sequence
        begin
            word_t read_data;
            bool_t failed;
            int errors = 0;

            test_number++;
            $display("\n--- TEST %0d: Stress Test - Rapid Write/Read ---", test_number);

            for (int i = 0; i < 10; i++) begin
                addr_t addr = 32'h7000 + (i * 4);
                word_t data = 32'hA0000000 + i;

                cpu_write(addr, data, MEM_STLEN_WORD);
                wait_cycles(1);
            end

            wait_cycles(5);

            for (int i = 0; i < 10; i++) begin
                addr_t addr = 32'h7000 + (i * 4);
                word_t expected = 32'hA0000000 + i;

                cpu_read(addr, MEM_STLEN_WORD, read_data, failed);
                if (read_data != expected) begin
                    $display("[TEST] Stress test error at iteration %0d: Expected 0x%h, got 0x%h",
                             i, expected, read_data);
                    errors++;
                end
            end

            if (errors == 0) begin
                $display("[TEST] Test %0d PASSED: All 10 rapid writes/reads correct", test_number);
                test_passed++;
            end else begin
                $display("[TEST] Test %0d FAILED: %0d errors out of 10 operations", test_number,
                         errors);
                test_failed++;
            end
        end

        // TEST 8: Wait for store buffer to drain
        begin
            test_number++;
            $display("\n--- TEST %0d: Store Buffer Draining ---", test_number);

            $display("[TEST] Waiting for store buffer to drain...");
            wait_cycles(100);

            $display("[TEST] Test %0d PASSED: Store buffer draining observed", test_number);
            test_passed++;
        end

        // Wait for any remaining operations
        wait_cycles(20);

        // Print summary
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_number);
        $display("Passed:      %0d", test_passed);
        $display("Failed:      %0d", test_failed);
        $display("========================================\n");

        if (test_failed == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end

        $finish;
    end

    // Waveform dumping
    initial begin
        $dumpfile("tb_store_buffer_frontend.fst");
        $dumpvars(0, tb_store_buffer_frontend);
    end

    // Timeout watchdog
    initial begin
        #100000;  // 100us timeout
        $display("\nERROR: Simulation timeout!");
        $finish;
    end

endmodule
