`timescale 1ns / 1ps

module tb_store_buffer;

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

    // DUT signals
    addr_t readAddr;
    word_t readData;
    bool_t readHit;

    bool_t sbCanWrite;
    bool_t writeRequest;
    addr_t writeAddr;
    word_t writeData;
    mem_stlen_t writeDataLen;

    bool_t interrupt;
    bool_t interrupted;

    cache_writeonly_request_if cacheRequest ();

    // DUT instantiation
    store_buffer dut (
        .clk(clk),
        .readAddr(readAddr),
        .readData(readData),
        .readHit(readHit),
        .sbCanWrite(sbCanWrite),
        .writeRequest(writeRequest),
        .writeAddr(writeAddr),
        .writeData(writeData),
        .writeDataLen(writeDataLen),
        .interrupt(interrupt),
        .interrupted(interrupted),
        .cacheRequest(cacheRequest.master)
    );

    // Mock cache (slave side)
    typedef enum logic [1:0] {
        CACHE_IDLE,
        CACHE_PROCESSING,
        CACHE_READY
    } cache_state_t;

    cache_state_t cacheState;
    logic [31:0] cache_memory[1024*1024];  // Associative array for cache storage
    int cache_delay;  // Configurable delay for cache operations

    initial begin
        cacheState = CACHE_IDLE;
        cacheRequest.ready = 1'b0;
        cache_delay = 0;
    end

    // Mock cache behavior
    always_ff @(posedge clk) begin
        case (cacheState)
            CACHE_IDLE: begin
                $display("  [CACHE] @%0d Cache state: CACHE_IDLE, ready=%0b", cycle_count,
                         cacheRequest.ready);
                cacheRequest.ready <= 1'b0;
                // if (cacheRequest.request) begin
                //     if (cache_delay == 0) begin
                //         // Process immediately
                //         // Use blocking assignment for associative array
                //         $display(
                //             "  [CACHE] @%0d Completed: write addr=0x%h data=0x%h len=%0d VISIBLE NEXT CYCLE",
                //             cycle_count, cacheRequest.addr, cacheRequest.dataToCache,
                //             cacheRequest.dataLen);
                //         cache_memory[cacheRequest.addr] <= cacheRequest.dataToCache;
                //         cacheRequest.ready <= 1'b1;
                //         cacheState <= CACHE_READY;
                //     end else begin
                $display("  [CACHE] @%0d Received: write addr=0x%h data=0x%h len=%0d", cycle_count,
                         cacheRequest.addr, cacheRequest.dataToCache, cacheRequest.dataLen);
                cacheState <= CACHE_PROCESSING;
                // end
                // end
            end
            CACHE_PROCESSING: begin
                $display("  [CACHE] @%0d Cache state: CACHE_PROCESSING, ready=%0b", cycle_count,
                         cacheRequest.ready);
                if (cache_delay >= 1) cache_delay <= cache_delay - 1;
                $display("[CACHE] @%0d Processing cache write, delay remaining=%0d", cycle_count,
                         cache_delay - 1);
                if (cache_delay == 0) begin
                    // Delay will be 0 next cycle, complete the write
                    cache_memory[cacheRequest.addr] <= cacheRequest.dataToCache;
                    $display("  [CACHE] @%0d Write addr=0x%h data=0x%h len=%0d", cycle_count,
                             cacheRequest.addr, cacheRequest.dataToCache, cacheRequest.dataLen);
                    cacheRequest.ready <= 1'b1;
                    cacheState <= CACHE_READY;
                    $display(
                        "  [CACHE] @%0d Completed: write addr=0x%h data=0x%h len=%0d VISIBLE NEXT CYCLE",
                        cycle_count, cacheRequest.addr, cacheRequest.dataToCache,
                        cacheRequest.dataLen);
                end
            end
            CACHE_READY: begin
                $display("  [CACHE] @%0d Cache state: CACHE_READY, ready=%0b", cycle_count,
                         cacheRequest.ready);
                $display("  [CACHE] @%0d Cache write completed", cycle_count);
                // print cache contents
                for (int i = 0; i < 1024 * 1024; i++) begin
                    if (cache_memory[i] !== '0) begin
                        $display("    [CACHE] Addr 0x%h: Data 0x%h", i, cache_memory[i]);
                    end
                end
                cacheRequest.ready <= 1'b0;
                cacheState <= CACHE_IDLE;
            end
            default: begin
                cacheState <= CACHE_IDLE;
            end
        endcase
    end

    // Test variables
    integer passed = 0, failed = 0;
    integer test_num = 0;

    // Task to check results
    task automatic check_eq(string name, logic [31:0] actual, logic [31:0] expected);
        if (actual === expected) begin
            $display("  [PASS] @%0d Test %0d - %s: 0x%h == 0x%h", cycle_count, test_num, name,
                     actual, expected);
            passed++;
        end else begin
            $display("  [FAIL] @%0d Test %0d - %s: 0x%h != 0x%h (expected)", cycle_count, test_num,
                     name, actual, expected);
            failed++;
        end
    endtask

    task automatic check_bool(string name, logic actual, logic expected);
        if (actual === expected) begin
            $display("  [PASS] @%0d Test %0d - %s: %b == %b", cycle_count, test_num, name, actual,
                     expected);
            passed++;
        end else begin
            $display("  [FAIL] @%0d Test %0d - %s: %b != %b (expected)", cycle_count, test_num,
                     name, actual, expected);
            failed++;
        end
    endtask

    // Task to write to store buffer
    task automatic sb_write(input addr_t addr, input word_t data, input mem_stlen_t len);
        $display("@%0d  [SB] Writing addr=0x%h data=0x%h len=%0d", cycle_count, addr, data, len);
        wait (sbCanWrite);
        $display("@%0d: [SB] sbCanWrite is high, proceeding with write", cycle_count);
        @(posedge clk);  // Wait for clock edge first
        writeRequest = 1'b1;
        writeAddr = addr;
        writeData = data;
        writeDataLen = len;
        $display("@%0d: [SB] write issued: writeRequest=%b", cycle_count, writeRequest);
        @(posedge clk);  // Keep request high for one cycle
        writeRequest = 1'b0;
        $display("@%0d: [SB] writeRequest deasserted", cycle_count);
    endtask

    // Task to read from store buffer
    task automatic sb_read(input addr_t addr, output word_t data, output bool_t hit);
        readAddr = addr;
        $display("@%0d: [SB] Reading addr=0x%h", cycle_count, readAddr);
        #1;  // Allow combinational logic to settle
        data = readData;
        hit  = readHit;
        $display("@%0d: [SB] Read addr=0x%h data=0x%h hit=%b", cycle_count, addr, data, hit);
        @(posedge clk);
    endtask

    // Task to wait for interrupt acknowledgment
    task automatic wait_interrupt_ack();
        interrupt = 1'b1;
        wait (interrupted == 1'b1);
        $display("[SB] @%0d: Interrupt acknowledged", cycle_count);
        @(posedge clk);
        interrupt = 1'b0;
        @(posedge clk);
        $display("[SB] @%0d: Interrupt deasserted", cycle_count);
    endtask

    // Main test sequence
    initial begin
        $display("\n========================================");
        $display("Store Buffer Testbench Starting");
        $display("========================================\n");

        // Initialize signals
        readAddr = '0;
        writeRequest = 1'b0;
        writeAddr = '0;
        writeData = '0;
        writeDataLen = MEM_STLEN_WORD;
        interrupt = 1'b0;
        cache_delay = 0;

        // Reset
        repeat (5) @(posedge clk);

        // Test 1: Basic write and read (hit)
        test_num++;
        $display("\n@%0d Test %0d: Basic write and read (should hit)", cycle_count, test_num);
        sb_write(32'h1000, 32'hDEADBEEF, MEM_STLEN_WORD);
        begin
            word_t data;
            bool_t hit;
            sb_read(32'h1000, data, hit);
            check_bool("Read hit", hit, 1'b1);
            check_eq("Read data", data, 32'hDEADBEEF);
        end

        // Test 2: Read miss
        test_num++;
        $display("\n@%0d Test %0d: Read miss (different address)", cycle_count, test_num);
        begin
            word_t data;
            bool_t hit;
            sb_read(32'h2000, data, hit);
            check_bool("Read miss", hit, 1'b0);
        end

        // Test 3: Multiple writes (fill buffer)
        test_num++;
        $display("\n@%0d Test %0d: Multiple writes (fill buffer)", cycle_count, test_num);

        // Block cache to prevent draining so buffer actually fills
        cache_delay = 10;
        sb_write(32'h1004, 32'hAAAAAAAA, MEM_STLEN_WORD);
        sb_write(32'h1004, 32'hCAFEBABE, MEM_STLEN_WORD);
        sb_write(32'h1008, 32'h12345678, MEM_STLEN_WORD);
        sb_write(32'h100C, 32'hAAAAAAAA, MEM_STLEN_WORD);

        // Should be full now (4 entries) - cache is blocked so no draining
        @(posedge clk);
        check_bool("Buffer full", sbCanWrite, 1'b0);

        // Restore cache delay
        cache_delay = 0;

        // Test 4: Read from younger entry (should prefer younger)
        test_num++;
        $display("\n@%0d Test %0d: Overwrite same address, verify younger returned", cycle_count,
                 test_num);
        // // Wait for buffer to start draining to make room
        // @(posedge clk);
        // Write to same address again (younger entry)
        sb_write(32'h100C, 32'h87654321, MEM_STLEN_WORD);
        // Read should return the younger value
        begin
            word_t data;
            bool_t hit;
            sb_read(32'h100C, data, hit);
            check_bool("Read hit youngest", hit, 1'b1);
            check_eq("Read data youngest (should prefer younger)", data, 32'h87654321);
        end

        // Test 5: Draining to cache (wait for buffer to drain)
        test_num++;
        $display("\n@%0d Test %0d: Draining buffer to cache", cycle_count, test_num);
        cache_delay = 1;  // Add some delay to cache operations

        // Wait for draining to complete
        repeat (20) @(posedge clk);

        // Check that cache received all writes
        check_eq("Cache[0x1000]", cache_memory[32'h1000], 32'hDEADBEEF);
        check_eq("Cache[0x1004]", cache_memory[32'h1004], 32'hCAFEBABE);
        check_eq("Cache[0x1008]", cache_memory[32'h1008], 32'h12345678);
        check_eq("Cache[0x100C]", cache_memory[32'h100C], 32'h87654321);

        // Test 6: Write after drain (buffer should be empty and accept writes)
        test_num++;
        $display("\n@%0d Test %0d: Write after drain", cycle_count, test_num);
        cache_delay = 0;
        sb_write(32'h2000, 32'hAABBCCDD, MEM_STLEN_WORD);

        begin
            word_t data;
            bool_t hit;
            sb_read(32'h2000, data, hit);
            check_bool("Read hit after drain", hit, 1'b1);
            check_eq("Read data after drain", data, 32'hAABBCCDD);
        end

        // Test 7: Interrupt handling (interrupt while idle)
        test_num++;
        $display("\n@%0d Test %0d: Interrupt while idle", cycle_count, test_num);
        repeat (10) @(posedge clk);  // Wait for drain
        wait_interrupt_ack();
        $display("  [PASS] Interrupt handled while idle");
        passed++;

        // Test 8: Interrupt while draining
        test_num++;
        $display("\n@%0d Test %0d: Interrupt while draining", cycle_count, test_num);
        cache_delay = 3;  // Slow cache to allow interrupt during drain

        // Fill buffer
        sb_write(32'h3000, 32'h11111111, MEM_STLEN_WORD);
        sb_write(32'h3004, 32'h22222222, MEM_STLEN_WORD);
        sb_write(32'h3008, 32'h33333333, MEM_STLEN_WORD);

        // Wait a bit for draining to start
        repeat (1) @(posedge clk);

        // Send interrupt
        wait_interrupt_ack();

        // Wait and check that draining resumes after interrupt clears
        $display("\n@%0d Test %0d (continued): Start checking", cycle_count, test_num);
        cache_delay = 0;
        repeat (20) @(posedge clk);

        check_eq("Cache[0x3000]", cache_memory[32'h3000], 32'h11111111);
        check_eq("Cache[0x3004]", cache_memory[32'h3004], 32'h22222222);
        check_eq("Cache[0x3008]", cache_memory[32'h3008], 32'h33333333);

        // Test 9: Different data lengths
        test_num++;
        $display("\n@%0d Test %0d: Different data lengths", cycle_count, test_num);
        sb_write(32'h4000, 32'h000000AB, MEM_STLEN_BYTE);
        sb_write(32'h4004, 32'h0000ABCD, MEM_STLEN_HALF);
        sb_write(32'h4008, 32'hABCDEF01, MEM_STLEN_WORD);

        repeat (15) @(posedge clk);

        check_eq("Cache[0x4000] byte", cache_memory[32'h4000], 32'h000000AB);
        check_eq("Cache[0x4004] half", cache_memory[32'h4004], 32'h0000ABCD);
        check_eq("Cache[0x4008] word", cache_memory[32'h4008], 32'hABCDEF01);

        // Test 10: Overwriting same address (younger should be visible)
        test_num++;
        $display("\n@%0d Test %0d: Overwriting same address", cycle_count, test_num);
        sb_write(32'h5000, 32'h11111111, MEM_STLEN_WORD);
        sb_write(32'h5000, 32'h22222222, MEM_STLEN_WORD);

        begin
            word_t data;
            bool_t hit;
            sb_read(32'h5000, data, hit);
            check_bool("Read hit overwrite", hit, 1'b1);
            check_eq("Read data overwrite (should be newer)", data, 32'h22222222);
        end

        // Wait for drain and check cache got the latest value
        repeat (10) @(posedge clk);
        // Note: Both writes will go to cache, but the second one should overwrite
        check_eq("Cache[0x5000] final", cache_memory[32'h5000], 32'h22222222);

        // Final wait
        repeat (10) @(posedge clk);

        // Print summary
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Passed: %0d", passed);
        $display("Failed: %0d", failed);
        if (failed == 0) begin
            $display("\nALL TESTS PASSED!");
        end else begin
            $display("\nSOME TESTS FAILED!");
        end
        $display("========================================\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #50000;  // 50us timeout
        $display("\n[ERROR] Testbench timeout!");
        $display("Passed: %0d", passed);
        $display("Failed: %0d", failed);
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_store_buffer.vcd");
        $dumpvars(0, tb_store_buffer);
    end

endmodule
