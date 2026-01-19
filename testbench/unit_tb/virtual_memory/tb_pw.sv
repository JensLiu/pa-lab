`timescale 1ns / 1ps

module tb_page_walker;
    import pkg_virtual_memory::*;
    import pkg_global_defs::*;

    logic clk, rst_n;

    mmu_pw_if pw_if ();
    pw_cache_if cache_if ();

    // DUT
    page_walker dut (
        .clk(clk),
        .rst_n(rst_n),
        .pw_mmu_if(pw_if),
        .pw_cache_if(cache_if)
    );

    // ============================================================================
    // Simple memory model with 1-cycle latency
    // ============================================================================
    typedef logic [31:0] word_t;
    word_t mem[addr_t];  // associative array

    logic pending;
    addr_t pend_addr;
    logic pend_is_write;
    word_t pend_wdata;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending        <= 0;
            cache_if.ready <= 0;
            cache_if.rdata <= '0;
            cache_if.fault <= 0;
        end else begin
            cache_if.ready <= 0;

            if (pending) begin
                cache_if.ready <= 1;
                cache_if.fault <= 0;

                if (pend_is_write) begin
                    mem[pend_addr] = pend_wdata;  // Blocking assignment for associative array
                    cache_if.rdata <= '0;
                end else begin
                    cache_if.rdata <= mem.exists(pend_addr) ? mem[pend_addr] : 32'h0;
                end
                pending <= 0;
            end

            if (cache_if.req && !pending) begin
                pending       <= 1;
                pend_addr     <= cache_if.addr;
                pend_is_write <= cache_if.is_write;
                pend_wdata    <= cache_if.wdata;
            end
        end
    end

    // ============================================================================
    // Clock generation
    // ============================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ============================================================================
    // VCD dump
    // ============================================================================
    initial begin
        $dumpfile("build/tb_pw.vcd");
        $dumpvars(0, tb_page_walker);
    end

    // ============================================================================
    // Timeout
    // ============================================================================
    initial begin : timeout_block
        #50000;
        $fatal(1, "[PW] TIMEOUT");
    end

    // ============================================================================
    // Reset and default signals
    // ============================================================================
    task automatic drive_defaults();
        pw_if.req            = 0;
        pw_if.satp           = '0;
        pw_if.vaddr          = '0;
        pw_if.access_type    = ACCESS_NONE;
        pw_if.curr_priv_mode = USER_MODE;
        pw_if.update_ad      = 0;
        pw_if.set_a          = 0;
        pw_if.set_d          = 0;
    endtask

    task automatic apply_reset();
        rst_n = 0;
        drive_defaults();
        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

    // ============================================================================
    // Helpers Sv32
    // ============================================================================
    function automatic addr_t mk_pte_addr(input ppn_t base_ppn, input logic [9:0] idx);
        addr_t base;
        base = {base_ppn, 12'b0};
        return base + {idx, 2'b00};  // idx * 4
    endfunction

    function automatic pte_sv32_t make_pte_leaf(input ppn_t ppn, input logic r, w, x, u, g, a, d,
                                                input logic v);
        pte_sv32_t p;
        p = '0;
        p.ppn = ppn;
        p.r = r;
        p.w = w;
        p.x = x;
        p.u = u;
        p.g = g;
        p.a = a;
        p.d = d;
        p.v = v;
        return p;
    endfunction

    function automatic pte_sv32_t make_pte_ptr(input ppn_t next_level_ppn, input logic v);
        pte_sv32_t p;
        p = '0;
        p.ppn = next_level_ppn;
        p.v = v;
        // Non-leaf: r=w=x=0
        return p;
    endfunction

    // Write PTE to memory (immediate, not clocked)
    task automatic mem_write_pte(input addr_t addr, input pte_sv32_t pte);
        mem[addr] = word_t'(pte);
    endtask

    // Read PTE from memory
    function automatic pte_sv32_t mem_read_pte(input addr_t addr);
        if (mem.exists(addr)) return pte_sv32_t'(mem[addr]);
        else return '0;
    endfunction

    // ============================================================================
    // Start a page walk request
    // Drive signals at negedge for proper timing
    // ============================================================================
    task automatic start_walk(input satp_register_t satp, input vaddr_t vaddr,
                              input access_type_t acc, input priv_mode_t priv,
                              input logic update_ad, input logic set_a, input logic set_d);
        // Wait for page walker to be idle before starting new walk
        while (pw_if.busy) begin
            @(posedge clk);
            #1;
        end

        @(negedge clk);
        pw_if.satp           = satp;
        pw_if.vaddr          = vaddr;
        pw_if.access_type    = acc;
        pw_if.curr_priv_mode = priv;
        pw_if.update_ad      = update_ad;
        pw_if.set_a          = set_a;
        pw_if.set_d          = set_d;
        pw_if.req            = 1;

        @(posedge clk);  // DUT captures request here
        #1;

        // Verify the walk actually started
        if (!pw_if.busy) begin
            // Hold req for another cycle if needed
            @(posedge clk);
            #1;
        end

        @(negedge clk);
        pw_if.req = 0;  // Deassert after walk has started
    endtask

    // ============================================================================
    // Wait for response
    // ============================================================================
    // Response storage
    logic       resp_page_fault;
    page_fault_t resp_fault_cause;
    ppn_t       resp_ppn;
    
    task automatic wait_resp();
        int timeout_cnt;
        timeout_cnt = 0;
        while (!pw_if.ready) begin
            @(posedge clk);
            #1;
            timeout_cnt++;
            if (timeout_cnt > 200) begin
                $display("[PW DEBUG] timeout! busy=%b, ready=%b, state=%s", pw_if.busy,
                         pw_if.ready, dut.pw_state_q.name());
                $fatal(1, "[PW] wait_resp timeout after 200 cycles");
            end
        end
        // Capture response values before they are cleared
        resp_page_fault = pw_if.page_fault;
        resp_fault_cause = pw_if.fault_cause;
        resp_ppn = pw_if.ppn;
        
        // Wait an extra cycle to ensure any pending memory writes complete
        @(posedge clk);
        #1;
    endtask

    // ============================================================================
    // Check response - uses captured response values
    // ============================================================================
    task automatic check_ok(input ppn_t exp_ppn, input string test_name);
        if (resp_page_fault) begin
            $fatal(1, "[PW] %s: esperado OK, got page_fault (cause=%s)", test_name,
                   resp_fault_cause.name());
        end
        if (resp_ppn !== exp_ppn) begin
            $fatal(1, "[PW] %s: ppn mismatch exp=%h got=%h", test_name, exp_ppn, resp_ppn);
        end
        $display("[PW] %s: OK (ppn=%h)", test_name, resp_ppn);
    endtask

    task automatic check_fault(input page_fault_t exp_cause, input string test_name);
        if (!resp_page_fault) begin
            $fatal(1, "[PW] %s: esperado fault, got OK", test_name);
        end
        if (resp_fault_cause !== exp_cause) begin
            $fatal(1, "[PW] %s: fault cause mismatch exp=%s got=%s", test_name, exp_cause.name(),
                   resp_fault_cause.name());
        end
        $display("[PW] %s: FAULT OK (cause=%s)", test_name, resp_fault_cause.name());
    endtask

    // ============================================================================
    // Tests
    // ============================================================================
    initial begin : test_seq
        satp_register_t satp;
        vaddr_t         vaddr;
        logic [9:0] vpn1, vpn0;

        ppn_t l1_ppn, l0_ppn, leaf_ppn;
        addr_t l1_addr, l0_addr;
        pte_sv32_t pte_l1, pte_l0, pte_check;

        // Variables for TEST10
        vaddr_t vaddr2;
        logic [9:0] vpn1_2, vpn0_2;
        addr_t l1_addr2, l0_addr2;
        ppn_t leaf_ppn2;

        apply_reset();

        // =========================================================================
        // Setup page tables
        // =========================================================================
        l1_ppn = 20'h00100;  // L1 table base (satp.ppn)
        l0_ppn = 20'h00200;  // L0 table base
        leaf_ppn = 20'hABCDE;  // Target physical page

        satp = '0;
        satp.ppn = l1_ppn;
        satp.asid = 1;
        satp.mode = 1;  // SV32 enabled

        // Virtual address to translate
        vaddr = 32'h1234_5678;
        vpn1 = vaddr[31:22];  // = 0x048
        vpn0 = vaddr[21:12];  // = 0x145

        $display("\n[PW] VA=%h => vpn1=%h vpn0=%h offset=%h", vaddr, vpn1, vpn0, vaddr[11:0]);

        // L1[vpn1] => pointer to L0
        l1_addr = mk_pte_addr(l1_ppn, vpn1);
        pte_l1  = make_pte_ptr(l0_ppn, 1'b1);
        mem_write_pte(l1_addr, pte_l1);
        $display("[PW] L1 PTE @ %h = %h (ptr to L0)", l1_addr, pte_l1);

        // L0[vpn0] => leaf page with RWXU, A=0, D=0
        l0_addr = mk_pte_addr(l0_ppn, vpn0);
        pte_l0  = make_pte_leaf(leaf_ppn, 1, 1, 1, 1, 0, 0, 0, 1);
        mem_write_pte(l0_addr, pte_l0);
        $display("[PW] L0 PTE @ %h = %h (leaf)", l0_addr, pte_l0);

        // =========================================================================
        $display("\n========== TEST 1: LOAD exitoso ==========");
        // =========================================================================
        start_walk(satp, vaddr, ACCESS_LOAD, USER_MODE, 0, 0, 0);
        wait_resp();
        check_ok(leaf_ppn, "TEST1");

        // =========================================================================
        $display("\n========== TEST 2: IFETCH con X=0 => fault ==========");
        // =========================================================================
        pte_l0 = make_pte_leaf(leaf_ppn, 1, 1, 0, 1, 0, 1, 1, 1);  // X=0
        mem_write_pte(l0_addr, pte_l0);

        start_walk(satp, vaddr, ACCESS_IFETCH, USER_MODE, 0, 0, 0);
        wait_resp();
        check_fault(PAGE_FAULT_IFETCH, "TEST2");

        // =========================================================================
        $display("\n========== TEST 3: STORE con W=0 => fault ==========");
        // =========================================================================
        pte_l0 = make_pte_leaf(leaf_ppn, 1, 0, 1, 1, 0, 1, 1, 1);  // W=0
        mem_write_pte(l0_addr, pte_l0);

        start_walk(satp, vaddr, ACCESS_STORE, USER_MODE, 0, 0, 0);
        wait_resp();
        check_fault(PAGE_FAULT_STORE, "TEST3");

        // =========================================================================
        $display("\n========== TEST 4: LOAD con R=0 => fault ==========");
        // =========================================================================
        pte_l0 = make_pte_leaf(leaf_ppn, 0, 0, 1, 1, 0, 1, 1, 1);  // R=0, X=1 (valid leaf)
        mem_write_pte(l0_addr, pte_l0);

        start_walk(satp, vaddr, ACCESS_LOAD, USER_MODE, 0, 0, 0);
        wait_resp();
        check_fault(PAGE_FAULT_LOAD, "TEST4");

        // =========================================================================
        $display("\n========== TEST 5: USER_MODE con U=0 => fault ==========");
        // =========================================================================
        pte_l0 = make_pte_leaf(leaf_ppn, 1, 1, 1, 0, 0, 1, 1, 1);  // U=0
        mem_write_pte(l0_addr, pte_l0);

        start_walk(satp, vaddr, ACCESS_LOAD, USER_MODE, 0, 0, 0);
        wait_resp();
        check_fault(PAGE_FAULT_LOAD, "TEST5");

        // =========================================================================
        $display("\n========== TEST 6: V=0 en L1 => fault ==========");
        // =========================================================================
        pte_l1 = make_pte_ptr(l0_ppn, 1'b0);  // V=0
        mem_write_pte(l1_addr, pte_l1);

        start_walk(satp, vaddr, ACCESS_LOAD, USER_MODE, 0, 0, 0);
        wait_resp();
        check_fault(PAGE_FAULT_LOAD, "TEST6");

        // Restore L1
        pte_l1 = make_pte_ptr(l0_ppn, 1'b1);
        mem_write_pte(l1_addr, pte_l1);

        // =========================================================================
        $display("\n========== TEST 7: V=0 en L0 => fault ==========");
        // =========================================================================
        pte_l0 = make_pte_leaf(leaf_ppn, 1, 1, 1, 1, 0, 1, 1, 0);  // V=0
        mem_write_pte(l0_addr, pte_l0);

        start_walk(satp, vaddr, ACCESS_LOAD, USER_MODE, 0, 0, 0);
        wait_resp();
        check_fault(PAGE_FAULT_LOAD, "TEST7");

        // =========================================================================
        $display("\n========== TEST 8: STORE con update A/D ==========");
        // =========================================================================
        pte_l0 = make_pte_leaf(leaf_ppn, 1, 1, 1, 1, 0, 0, 0, 1);  // A=0, D=0
        mem_write_pte(l0_addr, pte_l0);

        start_walk(satp, vaddr, ACCESS_STORE, USER_MODE, 1, 1, 1);  // update_ad, set_a, set_d
        wait_resp();
        check_ok(leaf_ppn, "TEST8");

        // Verify A/D were updated in memory
        pte_check = mem_read_pte(l0_addr);
        if (!pte_check.a || !pte_check.d) begin
            $fatal(1, "[PW] TEST8: A/D not updated (a=%0d d=%0d)", pte_check.a, pte_check.d);
        end
        $display("[PW] TEST8: A/D bits updated correctly (a=%0d d=%0d)", pte_check.a, pte_check.d);

        // =========================================================================
        $display("\n========== TEST 9: LOAD con update A (solo A) ==========");
        // =========================================================================
        pte_l0 = make_pte_leaf(leaf_ppn, 1, 1, 1, 1, 0, 0, 0, 1);  // A=0, D=0
        mem_write_pte(l0_addr, pte_l0);

        start_walk(satp, vaddr, ACCESS_LOAD, USER_MODE, 1, 1, 0);  // set_a=1, set_d=0
        wait_resp();
        check_ok(leaf_ppn, "TEST9");

        pte_check = mem_read_pte(l0_addr);
        if (!pte_check.a) begin
            $fatal(1, "[PW] TEST9: A not updated");
        end
        // D should not change for LOAD
        $display("[PW] TEST9: A bit updated (a=%0d d=%0d)", pte_check.a, pte_check.d);

        // =========================================================================
        $display("\n========== TEST 10: Direccion diferente ==========");
        // =========================================================================
        vaddr2 = 32'hDEAD_BEEF;
        vpn1_2 = vaddr2[31:22];
        vpn0_2 = vaddr2[21:12];
        leaf_ppn2 = 20'h12345;

        l1_addr2 = mk_pte_addr(l1_ppn, vpn1_2);
        pte_l1 = make_pte_ptr(l0_ppn, 1'b1);  // Same L0 table
        mem_write_pte(l1_addr2, pte_l1);

        l0_addr2 = mk_pte_addr(l0_ppn, vpn0_2);
        pte_l0   = make_pte_leaf(leaf_ppn2, 1, 1, 1, 1, 0, 1, 1, 1);
        mem_write_pte(l0_addr2, pte_l0);

        start_walk(satp, vaddr2, ACCESS_LOAD, USER_MODE, 0, 0, 0);
        wait_resp();
        check_ok(leaf_ppn2, "TEST10");

        // =========================================================================
        $display("\n========== ALL TESTS PASSED ==========\n");
        // =========================================================================
        $finish;
    end

endmodule
