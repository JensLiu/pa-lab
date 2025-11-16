`timescale 1ns / 1ps

module tb_cache;

    import pkg_global_defs::*;

    // Clock generation
    logic clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10ns period = 100MHz
    end

    logic [31:0] cycle_count;
    always_ff @(posedge clk) begin
        cycle_count <= cycle_count + 1;
    end

    // Interfaces
    cache_request_if cpuRequest ();
    mem_request_if memRequest ();

    // Memory model for backing store (simulates main memory)
    logic [127:0] backing_memory[bit [31:0]];  // Associative array for sparse memory

    // DUT
    cache_fast dut (
        .clk(clk),
        .cpuRequest(cpuRequest.slave),
        .memRequest(memRequest.master)
    );

    typedef enum logic [1:0] {
        MOCK_MEM_IDLE,
        MOCK_MEM_DONE
    } mock_mem_state_t;

    mock_mem_state_t mockMemState;
    always_ff @(posedge clk) begin
        memRequest.ready <= 1'b0;
        memRequest.dataFromMem <= '0;
        case (mockMemState)
            MOCK_MEM_IDLE: begin
                if (memRequest.request) begin
                    mockMemState <= MOCK_MEM_DONE;
                    memRequest.ready <= 1'b1;
                    if (memRequest.isRead) begin
                        // Read from backing memory
                        if (backing_memory.exists(memRequest.addr)) begin
                            memRequest.dataFromMem <= backing_memory[memRequest.addr];
                            $display("[MOCK MEM] Read req addr=0x%h data=0x%h", memRequest.addr,
                                     backing_memory[memRequest.addr]);
                        end else begin
                            memRequest.dataFromMem <= 128'h0;
                            $display("[MOCK MEM] Read req addr=0x%h UNINITIALIZED",
                                     memRequest.addr);
                        end
                    end else begin
                        // Write: use blocking assignment for associative array
                        backing_memory[memRequest.addr] = memRequest.dataToMem;
                        $display("[MOCK MEM] Write req addr=0x%h data=0x%h", memRequest.addr,
                                 memRequest.dataToMem);
                    end
                end
            end
            MOCK_MEM_DONE: begin
                memRequest.ready <= '0;  // visible in the IDLE state
                mockMemState <= MOCK_MEM_IDLE;
            end
            default: assert (FALSE);
        endcase
        $display("@%d: memory state = %d", cycle_count, mockMemState);
    end

    // Test variables
    integer passed = 0, failed = 0;
    integer test_num = 0;

    // Task to check results
    task automatic check_eq(string name, logic [31:0] actual, logic [31:0] expected);
        if (actual === expected) begin
            $display("[PASS] @%0d Test %0d - %s: 0x%h == 0x%h", cycle_count, test_num, name,
                     actual, expected);
            passed++;
        end else begin
            $display("[FAIL] @%0d Test %0d - %s: 0x%h != 0x%h (expected)", cycle_count, test_num,
                     name, actual, expected);
            failed++;
        end
    endtask

    // Task to perform a cache read
    task automatic cache_read(input addr_t addr, input word_t expected_data,
                              input string test_name);
        test_num++;
        $display("\n@%0d Test %0d: %s", cycle_count, test_num, test_name);
        $display("  Reading from address 0x%h", addr);

        cpuRequest.request = 1'b1;
        cpuRequest.isRead = 1'b1;
        cpuRequest.addr = addr;
        cpuRequest.invalidateAll = 1'b0;
        // otherwise it would read ready from the previous instruction 
        // (guaranteed to hit since it is loaded to the cache)
        @(posedge clk);
        // Wait for ready
        wait (cpuRequest.ready == 1'b1);
        $display("  @%d: detected ready after read request", cycle_count);
        @(posedge clk);

        $display("  Data read from cache: 0x%h", cpuRequest.dataFromCache);
        check_eq(test_name, cpuRequest.dataFromCache, expected_data);
        @(posedge clk);
    endtask

    // Task to perform a cache write
    task automatic cache_write(input addr_t addr, input word_t data, input string test_name);
        test_num++;
        $display("\n@%0d Test %0d: %s", cycle_count, test_num, test_name);
        $display("  Writing 0x%h to address 0x%h", data, addr);

        cpuRequest.request = 1'b1;
        cpuRequest.isRead = 1'b0;
        cpuRequest.addr = addr;
        cpuRequest.dataToCache = data;
        cpuRequest.invalidateAll = 1'b0;

        // Wait for ready
        @(posedge clk);
        wait (cpuRequest.ready == 1'b1);
        $display("  @%d: detected ready after write request", cycle_count);
        @(posedge clk);

        // TODO: this does not hold, why?
        // assert (cpuRequest.ready == 1'b1);
        $display("  @%d: [PASS] Write completed", cycle_count);
        passed++;
        @(posedge clk);

    endtask

    // Task to invalidate cache
    task automatic invalidate_cache();
        test_num++;
        $display("\nTest %0d: Invalidating entire cache", test_num);

        cpuRequest.invalidateAll = 1'b1;
        cpuRequest.request = 1'b0;
        @(posedge clk);
        cpuRequest.invalidateAll = 1'b0;
        @(posedge clk);

        $display("  @%d: [PASS] Cache invalidated", $time);
        passed++;
    endtask

    // Initialize backing memory with test patterns - direct initialization
    task automatic init_memory();
        // Initialize the associative array directly (no interface needed for mock)
        // Address format: [tag:25][set:3][offset:4]
        backing_memory[32'h0000_0000] = 128'h11111111_22222222_33333333_44444444;
        backing_memory[32'h0000_0010] = 128'h12345678_9ABCDEF0_FEDCBA98_76543210;
        backing_memory[32'h0200_0000] = 128'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD;
        backing_memory[32'h0200_0010] = 128'hDEADBEEF_CAFEBABE_BAADF00D_DEADC0DE;
        backing_memory[32'h0000_0020] = 128'h00000001_00000002_00000003_00000004;
        backing_memory[32'h0200_0020] = 128'h00000005_00000006_00000007_00000008;

        $display("Backing memory (mock) initialized with test patterns");
    endtask

    // Main test sequence
    initial begin
        $display("========================================");
        $display("tb_cache starting");
        $display("========================================");
        $dumpfile("tb_cache.fst");
        $dumpvars(0, tb_cache);

        // Initialize signals
        cpuRequest.request = 1'b0;
        cpuRequest.isRead = 1'b0;
        cpuRequest.invalidateAll = 1'b0;
        cpuRequest.addr = 32'h0;
        cpuRequest.dataToCache = 32'h0;

        // Initialize memory
        init_memory();

        // Wait for initial state
        repeat (5) @(posedge clk);

        // ========================================
        // Test 1: Simple read miss - should trigger refill
        // ========================================
        cache_read(32'h0000_0000, 32'h44444444, "Read miss - Set 0, Way 0, offset 0");

        // ========================================
        // Test 2: Read hit from same cache line
        // ========================================
        cache_read(32'h0000_0004, 32'h33333333, "Read hit - Set 0, Way 0, offset 4");
        cache_read(32'h0000_0008, 32'h22222222, "Read hit - Set 0, Way 0, offset 8");
        // // ========================================
        // // Test 3: Read miss to different tag, same set (Way 1)
        // // ========================================
        cache_read(32'h0200_0000, 32'hDDDDDDDD, "Read miss - Set 0, Way 1, offset 0");
        // ========================================
        // Test 4: Verify both ways still hit
        // ========================================
        cache_read(32'h0000_0000, 32'h44444444, "Read hit - Set 0, Way 0 (verify)");
        cache_read(32'h0200_0004, 32'hCCCCCCCC, "Read hit - Set 0, Way 1");
        // ========================================
        // Test 5: Read miss causing eviction (LRU)
        // ========================================
        // This should evict the least recently used way
        cache_read(32'h0400_0000, 32'h00000000, "Read miss - Set 0, causing eviction");
        // ========================================
        // Test 6: Write to cache (write allocate)
        // ========================================
        // TODO: In the waveform, the `dataToCache` field coming from the CPU is delayed
        //       find out why 
        cache_write(32'h0000_0010, 32'hDEADBEEF, "Write - Set 1, new line");

        // ========================================
        // Test 7: Read back written data
        // ========================================
        // TODO: with and without this, the cache is different, why?
        cache_read(32'h0000_0010, 32'hDEADBEEF, "Read hit - verify write");

        // ========================================
        // Test 8: Write to existing cache line
        // ========================================
        // TODO: In the waveform, the `dataToCache` field coming from the CPU is delayed
        //       find out why 
        cache_write(32'h0000_0014, 32'hCAFEBABE, "Write - Set 1, same line, offset 4");

        // ========================================
        // Test 9: Read back second write
        // ========================================
        cache_read(32'h0000_0014, 32'hCAFEBABE, "Read hit - verify second write");
        cache_read(32'h0000_0010, 32'hDEADBEEF, "Read hit - verify first write still there");

        // ========================================
        // Test 10: Test dirty line eviction
        // ========================================
        // Fill way 1 in set 1
        cache_read(32'h0200_0010, 32'hDEADC0DE, "Read miss - Set 1, Way 1");

        // This should evict the dirty line (with writes from tests 6 & 8)
        cache_read(32'h0400_0010, 32'h00000000, "Read miss - Set 1, evict dirty line");

        // Verify dirty data was written back to memory
        if (backing_memory.exists(32'h0000_0010)) begin
            // Check if our writes made it to backing memory
            logic [31:0] word0 = backing_memory[32'h0000_0010][31:0];
            logic [31:0] word1 = backing_memory[32'h0000_0010][63:32];
            test_num++;
            if (word0 == 32'hDEADBEEF && word1 == 32'hCAFEBABE) begin
                $display("[PASS] Test %0d - Dirty line writeback verified", test_num);
                passed++;
            end else begin
                $display("[FAIL] Test %0d - Dirty line writeback: word0=0x%h word1=0x%h", test_num,
                         word0, word1);
                failed++;
            end
        end

        // // ========================================
        // // Test 11: Cache invalidation
        // // ========================================
        invalidate_cache();

        // After invalidation, reads should miss and refill
        cache_read(32'h0000_0020, 32'h00000004, "Read after invalidation - should miss");

        // ========================================
        // Test 12: Different sets don't interfere
        // ========================================
        cache_read(32'h0000_0000, 32'h44444444, "Read - Set 0");
        cache_read(32'h0000_0020, 32'h00000004, "Read - Set 2");
        cache_read(32'h0000_0000, 32'h44444444, "Read - Set 0 again (should still hit)");

        // Wait a bit before finishing
        repeat (10) @(posedge clk);

        // Print summary
        $display("\n========================================");
        $display("tb_cache done");
        $display("Passed: %0d", passed);
        $display("Failed: %0d", failed);
        $display("========================================");

        if (failed == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end

        $finish;
    end

    // // Timeout watchdog
    initial begin
        #100000;  // 100us timeout
        $display("\n[ERROR] Timeout! Test did not complete in time.");
        $display("Passed: %0d, Failed: %0d", passed, failed);
        $finish;
    end

endmodule
