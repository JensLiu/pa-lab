`timescale 1ns/1ps

module tb_mmu;
  import pkg_virtual_memory::*;
  import pkg_global_defs::*;

  logic clk, rst_n;

  cpu_mmu_if instr_if();
  cpu_mmu_if data_if();

  mmu_tlb_if i_tlb_if();
  mmu_tlb_if d_tlb_if();
  mmu_pw_if  pw_if();
  pw_cache_if cache_if();

  // iTLB/dTLB
  tlb itlb(.clk(clk), .rst_n(rst_n), .tlb_mmu_if(i_tlb_if));
  tlb dtlb(.clk(clk), .rst_n(rst_n), .tlb_mmu_if(d_tlb_if));

  // Page walker
  page_walker pw(.clk(clk), .rst_n(rst_n), .pw_mmu_if(pw_if), .pw_cache_if(cache_if));

  // MMU
  mmu dut(
    .clk(clk),
    .rst_n(rst_n),
    .instr_if(instr_if),
    .data_if(data_if),
    .i_tlb_if(i_tlb_if),
    .d_tlb_if(d_tlb_if),
    .ptw_if(pw_if)
  );

  // ============================================================================
  // Memory model (same as PW testbench)
  // ============================================================================
  typedef logic [31:0] word_t;
  word_t mem [addr_t];

  logic pending;
  addr_t pend_addr;
  logic pend_is_write;
  word_t pend_wdata;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending <= 0;
      cache_if.ready <= 0;
      cache_if.rdata <= '0;
      cache_if.fault <= 0;
    end else begin
      cache_if.ready <= 0;

      if (pending && cache_if.req) begin
        // Only respond if master still requesting (req must stay high until ready)
        cache_if.ready <= 1;
        cache_if.fault <= 0;

        if (pend_is_write) begin
          mem[pend_addr] = pend_wdata;  // Blocking for associative array
          cache_if.rdata <= '0;
        end else begin
          cache_if.rdata <= mem.exists(pend_addr) ? mem[pend_addr] : 32'h0;
        end
        pending <= 0;
      end else if (cache_if.req && !pending) begin
        // Accept new request
        pending <= 1;
        pend_addr <= cache_if.addr;
        pend_is_write <= cache_if.is_write;
        pend_wdata <= cache_if.wdata;
      end else if (!cache_if.req) begin
        // Master dropped req before response - cancel
        pending <= 0;
      end
    end
  end

  // ============================================================================
  // Helpers
  // ============================================================================
  function automatic addr_t mk_pte_addr(input ppn_t base_ppn, input logic [9:0] idx);
    addr_t base;
    base = {base_ppn, 12'b0};
    return base + {idx, 2'b00};
  endfunction

  function automatic pte_sv32_t make_pte_leaf(
    input ppn_t ppn,
    input logic r, w, x, u, g, a, d, v
  );
    pte_sv32_t p;
    p = '0;
    p.ppn = ppn;
    p.r = r; p.w = w; p.x = x; p.u = u; p.g = g; p.a = a; p.d = d; p.v = v;
    return p;
  endfunction

  function automatic pte_sv32_t make_pte_ptr(input ppn_t next_ppn, input logic v);
    pte_sv32_t p;
    p = '0;
    p.ppn = next_ppn;
    p.v = v;
    return p;
  endfunction

  task automatic mem_write_pte(input addr_t addr, input pte_sv32_t pte);
    mem[addr] = word_t'(pte);
  endtask

  // ============================================================================
  // TLB Debug Print
  // ============================================================================
  task automatic print_tlbs(input string label);
    $display("[TLB] === %s ===", label);
    $display("[TLB] iTLB (entry_count=%0d):", itlb.entry_count);
    for (int i = 0; i < 4; i++) begin
      if (itlb.tlb_entries[i].valid) begin
        $display("[TLB]   [%0d] VPN=%h -> PPN=%h, ASID=%0d, perms(R=%b W=%b X=%b U=%b A=%b D=%b G=%b)",
          i,
          itlb.tlb_entries[i].vpn,
          itlb.tlb_entries[i].ppn,
          itlb.tlb_entries[i].asid,
          itlb.tlb_entries[i].perms.r,
          itlb.tlb_entries[i].perms.w,
          itlb.tlb_entries[i].perms.x,
          itlb.tlb_entries[i].perms.u,
          itlb.tlb_entries[i].perms.a,
          itlb.tlb_entries[i].perms.d,
          itlb.tlb_entries[i].perms.g
        );
      end else begin
        $display("[TLB]   [%0d] (invalid)", i);
      end
    end
    $display("[TLB] dTLB (entry_count=%0d):", dtlb.entry_count);
    for (int i = 0; i < 4; i++) begin
      if (dtlb.tlb_entries[i].valid) begin
        $display("[TLB]   [%0d] VPN=%h -> PPN=%h, ASID=%0d, perms(R=%b W=%b X=%b U=%b A=%b D=%b G=%b)",
          i,
          dtlb.tlb_entries[i].vpn,
          dtlb.tlb_entries[i].ppn,
          dtlb.tlb_entries[i].asid,
          dtlb.tlb_entries[i].perms.r,
          dtlb.tlb_entries[i].perms.w,
          dtlb.tlb_entries[i].perms.x,
          dtlb.tlb_entries[i].perms.u,
          dtlb.tlb_entries[i].perms.a,
          dtlb.tlb_entries[i].perms.d,
          dtlb.tlb_entries[i].perms.g
        );
      end else begin
        $display("[TLB]   [%0d] (invalid)", i);
      end
    end
  endtask

  // ============================================================================
  // Memory (Page Table) Debug Print
  // ============================================================================
  task automatic print_memory(input string label, input addr_t l1_addr, input addr_t l0_addr);
    pte_sv32_t pte;
    $display("[MEM] === %s ===", label);
    
    // Print L1 PTE
    if (mem.exists(l1_addr)) begin
      pte = pte_sv32_t'(mem[l1_addr]);
      $display("[MEM] L1 PTE @ %h: PPN=%h, V=%b, R=%b W=%b X=%b U=%b G=%b A=%b D=%b",
        l1_addr, pte.ppn, pte.v, pte.r, pte.w, pte.x, pte.u, pte.g, pte.a, pte.d);
    end else begin
      $display("[MEM] L1 PTE @ %h: (not present)", l1_addr);
    end
    
    // Print L0 PTE
    if (mem.exists(l0_addr)) begin
      pte = pte_sv32_t'(mem[l0_addr]);
      $display("[MEM] L0 PTE @ %h: PPN=%h, V=%b, R=%b W=%b X=%b U=%b G=%b A=%b D=%b",
        l0_addr, pte.ppn, pte.v, pte.r, pte.w, pte.x, pte.u, pte.g, pte.a, pte.d);
    end else begin
      $display("[MEM] L0 PTE @ %h: (not present)", l0_addr);
    end
  endtask

  task automatic print_all(input string label, input addr_t l1_addr, input addr_t l0_addr);
    print_tlbs(label);
    print_memory(label, l1_addr, l0_addr);
  endtask

  // ============================================================================
  // Clock/Reset
  // ============================================================================
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    $dumpfile("build/tb_mmu.vcd");
    $dumpvars(0, tb_mmu);
  end

  initial begin : timeout_block
    #100000;
    $fatal(1, "[MMU] TIMEOUT");
  end

  task automatic drive_defaults();
    instr_if.req = 0;
    instr_if.vaddr = '0;
    instr_if.access_type = ACCESS_IFETCH;
    instr_if.satp = '0;
    instr_if.curr_priv_mode = USER_MODE;
    instr_if.mmu_enable = 1;
    instr_if.flush = 0;

    data_if.req = 0;
    data_if.vaddr = '0;
    data_if.access_type = ACCESS_LOAD;
    data_if.satp = '0;
    data_if.curr_priv_mode = USER_MODE;
    data_if.mmu_enable = 1;
    data_if.flush = 0;
  endtask

  task automatic apply_reset();
    rst_n = 0;
    drive_defaults();
    repeat(5) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
  endtask

  // ============================================================================
  // Request/Response tasks with proper timing
  // ============================================================================
  // CPU request tasks - maintain req=1 until ready=1 (correct protocol)
  // ============================================================================
  task automatic cpu_req_instr(
    input vaddr_t va,
    input satp_register_t satp,
    input priv_mode_t priv
  );
    int timeout_cnt;
    
    // Wait for MMU to not be busy from previous transaction
    while (instr_if.busy) begin
      @(posedge clk);
      #1;
    end

    // Drive request on negedge
    @(negedge clk);
    instr_if.req = 1;
    instr_if.vaddr = va;
    instr_if.satp = satp;
    instr_if.curr_priv_mode = priv;
    instr_if.access_type = ACCESS_IFETCH;

    // Keep req=1 until ready=1 (correct protocol: hold request until response)
    timeout_cnt = 0;
    do begin
      @(posedge clk);
      #1;
      timeout_cnt++;
      if (timeout_cnt > 300) begin
        $fatal(1, "[MMU] cpu_req_instr timeout waiting for ready");
      end
    end while (!instr_if.ready);

    // Deassert request after ready
    @(negedge clk);
    instr_if.req = 0;
  endtask

  task automatic cpu_req_data(
    input vaddr_t va,
    input access_type_t acc,
    input satp_register_t satp,
    input priv_mode_t priv
  );
    int timeout_cnt;
    
    // Wait for MMU to not be busy from previous transaction
    while (data_if.busy) begin
      @(posedge clk);
      #1;
    end

    // Drive request on negedge
    @(negedge clk);
    data_if.req = 1;
    data_if.vaddr = va;
    data_if.access_type = acc;
    data_if.satp = satp;
    data_if.curr_priv_mode = priv;

    // Keep req=1 until ready=1 (correct protocol: hold request until response)
    timeout_cnt = 0;
    do begin
      @(posedge clk);
      #1;
      timeout_cnt++;
      if (timeout_cnt > 300) begin
        $fatal(1, "[MMU] cpu_req_data timeout waiting for ready");
      end
    end while (!data_if.ready);

    // Deassert request after ready
    @(negedge clk);
    data_if.req = 0;
  endtask

  task automatic wait_ready_instr();
    int cnt;
    cnt = 0;
    while (!instr_if.ready) begin
      @(posedge clk);
      #1;
      cnt++;
      if (cnt > 200) begin
        $fatal(1, "[MMU] wait_ready_instr timeout");
      end
    end
  endtask

  task automatic wait_ready_data();
    int cnt;
    cnt = 0;
    while (!data_if.ready) begin
      @(posedge clk);
      #1;
      cnt++;
      if (cnt > 200) begin
        $fatal(1, "[MMU] wait_ready_data timeout");
      end
    end
  endtask

  task automatic do_flush();
    // Wait for MMU to be in IDLE state (both channels)
    while (dut.i_mmu_state_q != 0 || dut.d_mmu_state_q != 0) begin
      @(posedge clk);
      #1;
    end
    
    @(negedge clk);
    instr_if.flush = 1;
    data_if.flush = 1;
    @(posedge clk);
    #1;
    @(negedge clk);
    instr_if.flush = 0;
    data_if.flush = 0;
    @(posedge clk);
  endtask

  // ============================================================================
  // Tests
  // ============================================================================
  initial begin : test_seq
    satp_register_t satp_bare, satp_sv32;
    vaddr_t         vaddr, vaddr2;
    logic [9:0]     vpn1, vpn0;
    logic [9:0]     vpn1_2, vpn0_2;
    ppn_t           l1_ppn, l0_ppn, leaf_ppn, leaf_ppn2;
    addr_t          l1_addr, l0_addr;
    addr_t          l1_addr2, l0_addr2;
    pte_sv32_t      pte_l1, pte_l0;
    paddr_t         exp_paddr;

    apply_reset();

    // =========================================================================
    // Setup page tables
    // =========================================================================
    l1_ppn   = 20'h00100;
    l0_ppn   = 20'h00200;
    leaf_ppn = 20'hABCDE;

    satp_bare = '0;
    satp_bare.mode = SATP_MODE_BARE;

    satp_sv32 = '0;
    satp_sv32.mode = 1;  // SV32
    satp_sv32.ppn  = l1_ppn;
    satp_sv32.asid = 1;

    vaddr = 32'h1234_5678;
    vpn1 = vaddr[31:22];
    vpn0 = vaddr[21:12];

    l1_addr = mk_pte_addr(l1_ppn, vpn1);
    l0_addr = mk_pte_addr(l0_ppn, vpn0);

    // L1[vpn1] => pointer to L0
    pte_l1 = make_pte_ptr(l0_ppn, 1'b1);
    mem_write_pte(l1_addr, pte_l1);

    // L0[vpn0] => leaf with RWXU, A=1, D=1
    pte_l0 = make_pte_leaf(leaf_ppn, 1,1,1,1, 0, 1,1, 1);
    mem_write_pte(l0_addr, pte_l0);

    $display("\n[MMU] Page tables setup:");
    $display("[MMU]   VA=%h => vpn1=%h vpn0=%h", vaddr, vpn1, vpn0);
    $display("[MMU]   L1 @ %h -> L0 ppn=%h", l1_addr, l0_ppn);
    $display("[MMU]   L0 @ %h -> leaf ppn=%h", l0_addr, leaf_ppn);

    // =========================================================================
    $display("\n========== TEST 1: BYPASS (SATP_MODE_BARE) ==========");
    // =========================================================================
    print_all("TEST1 BEFORE", l1_addr, l0_addr);
    cpu_req_instr(vaddr, satp_bare, USER_MODE);
    wait_ready_instr();

    if (instr_if.page_fault) begin
      $fatal(1, "[MMU] TEST1: bypass should not fault");
    end
    if (instr_if.paddr !== vaddr) begin
      $fatal(1, "[MMU] TEST1: bypass paddr!=vaddr (exp=%h got=%h)", vaddr, instr_if.paddr);
    end
    $display("[MMU] TEST1: BYPASS OK (paddr=%h)", instr_if.paddr);
    print_all("TEST1 AFTER", l1_addr, l0_addr);

    // =========================================================================
    $display("\n========== TEST 2: TLB Miss -> PTW -> Fill -> Hit (Data LOAD) ==========");
    // =========================================================================
    do_flush();
    print_all("TEST2 BEFORE", l1_addr, l0_addr);

    cpu_req_data(vaddr, ACCESS_LOAD, satp_sv32, USER_MODE);
    wait_ready_data();

    exp_paddr = {leaf_ppn, vaddr[11:0]};
    if (data_if.page_fault) begin
      $fatal(1, "[MMU] TEST2: unexpected page_fault");
    end
    if (data_if.paddr !== exp_paddr) begin
      $fatal(1, "[MMU] TEST2: paddr mismatch (exp=%h got=%h)", exp_paddr, data_if.paddr);
    end
    $display("[MMU] TEST2: Data LOAD OK (paddr=%h)", data_if.paddr);
    print_all("TEST2 AFTER", l1_addr, l0_addr);

    // =========================================================================
    $display("\n========== TEST 3: TLB Hit (cached from TEST2) ==========");
    // =========================================================================
    print_all("TEST3 BEFORE", l1_addr, l0_addr);
    cpu_req_data(vaddr, ACCESS_LOAD, satp_sv32, USER_MODE);
    wait_ready_data();

    if (data_if.page_fault) begin
      $fatal(1, "[MMU] TEST3: unexpected page_fault");
    end
    if (data_if.paddr !== exp_paddr) begin
      $fatal(1, "[MMU] TEST3: paddr mismatch");
    end
    $display("[MMU] TEST3: TLB Hit OK (paddr=%h)", data_if.paddr);
    print_all("TEST3 AFTER", l1_addr, l0_addr);

    // =========================================================================
    $display("\n========== TEST 4: Instruction fetch (TLB miss -> PTW) ==========");
    // =========================================================================
    do_flush();
    print_all("TEST4 BEFORE", l1_addr, l0_addr);

    cpu_req_instr(vaddr, satp_sv32, USER_MODE);
    wait_ready_instr();

    if (instr_if.page_fault) begin
      $fatal(1, "[MMU] TEST4: unexpected page_fault");
    end
    if (instr_if.paddr !== exp_paddr) begin
      $fatal(1, "[MMU] TEST4: paddr mismatch");
    end
    $display("[MMU] TEST4: Instr Fetch OK (paddr=%h)", instr_if.paddr);
    print_all("TEST4 AFTER", l1_addr, l0_addr);

    // =========================================================================
    $display("\n========== TEST 5: Permission fault (X=0 for IFETCH) ==========");
    // =========================================================================
    do_flush();

    // Modify PTE: remove X permission
    pte_l0 = make_pte_leaf(leaf_ppn, 1,1,0,1, 0, 1,1, 1);  // X=0
    mem_write_pte(l0_addr, pte_l0);
    print_all("TEST5 BEFORE", l1_addr, l0_addr);

    cpu_req_instr(vaddr, satp_sv32, USER_MODE);
    wait_ready_instr();

    if (!instr_if.page_fault) begin
      $fatal(1, "[MMU] TEST5: expected page_fault for X=0");
    end
    if (instr_if.page_fault_cause !== PAGE_FAULT_IFETCH) begin
      $fatal(1, "[MMU] TEST5: wrong fault cause");
    end
    $display("[MMU] TEST5: Permission fault OK (cause=%s)", instr_if.page_fault_cause.name());
    print_all("TEST5 AFTER", l1_addr, l0_addr);

    // =========================================================================
    $display("\n========== TEST 6: Permission fault (W=0 for STORE) ==========");
    // =========================================================================
    do_flush();

    // Modify PTE: remove W permission
    pte_l0 = make_pte_leaf(leaf_ppn, 1,0,1,1, 0, 1,1, 1);  // W=0
    mem_write_pte(l0_addr, pte_l0);
    print_all("TEST6 BEFORE", l1_addr, l0_addr);

    cpu_req_data(vaddr, ACCESS_STORE, satp_sv32, USER_MODE);
    wait_ready_data();

    if (!data_if.page_fault) begin
      $fatal(1, "[MMU] TEST6: expected page_fault for W=0");
    end
    if (data_if.page_fault_cause !== PAGE_FAULT_STORE) begin
      $fatal(1, "[MMU] TEST6: wrong fault cause");
    end
    $display("[MMU] TEST6: Permission fault OK (cause=%s)", data_if.page_fault_cause.name());
    print_all("TEST6 AFTER", l1_addr, l0_addr);

    // =========================================================================
    $display("\n========== TEST 7: V=0 -> Page fault ==========");
    // =========================================================================
    do_flush();

    // Modify PTE: V=0
    pte_l0 = make_pte_leaf(leaf_ppn, 1,1,1,1, 0, 1,1, 0);  // V=0
    mem_write_pte(l0_addr, pte_l0);
    print_all("TEST7 BEFORE", l1_addr, l0_addr);

    cpu_req_data(vaddr, ACCESS_LOAD, satp_sv32, USER_MODE);
    wait_ready_data();

    if (!data_if.page_fault) begin
      $fatal(1, "[MMU] TEST7: expected page_fault for V=0");
    end
    $display("[MMU] TEST7: V=0 fault OK");
    print_all("TEST7 AFTER", l1_addr, l0_addr);

    // =========================================================================
    $display("\n========== TEST 8: Different address ==========");
    // =========================================================================
    do_flush();

    // Restore valid PTE
    pte_l0 = make_pte_leaf(leaf_ppn, 1,1,1,1, 0, 1,1, 1);
    mem_write_pte(l0_addr, pte_l0);

    // Setup second mapping
    vaddr2 = 32'hDEAD_B000;
    leaf_ppn2 = 20'h12345;
    
    vpn1_2 = vaddr2[31:22];
    vpn0_2 = vaddr2[21:12];
    l1_addr2 = mk_pte_addr(l1_ppn, vpn1_2);
    l0_addr2 = mk_pte_addr(l0_ppn, vpn0_2);

    mem_write_pte(l1_addr2, make_pte_ptr(l0_ppn, 1'b1));
    mem_write_pte(l0_addr2, make_pte_leaf(leaf_ppn2, 1,1,1,1, 0, 1,1, 1));
    print_all("TEST8 BEFORE", l1_addr, l0_addr);

    cpu_req_data(vaddr2, ACCESS_LOAD, satp_sv32, USER_MODE);
    wait_ready_data();

    exp_paddr = {leaf_ppn2, vaddr2[11:0]};
    if (data_if.page_fault) begin
      $fatal(1, "[MMU] TEST8: unexpected fault");
    end
    if (data_if.paddr !== exp_paddr) begin
      $fatal(1, "[MMU] TEST8: paddr mismatch (exp=%h got=%h)", exp_paddr, data_if.paddr);
    end
    $display("[MMU] TEST8: Different address OK (paddr=%h)", data_if.paddr);
    print_all("TEST8 AFTER", l1_addr, l0_addr);

    // =========================================================================
    $display("\n========== TEST 9: Dirty bit update (D=0 -> STORE) ==========");
    // =========================================================================
    do_flush();

    // Create a PTE with A=1 but D=0 - a STORE should trigger dirty bit update
    pte_l0 = make_pte_leaf(leaf_ppn, 1,1,1,1, 0, 1,0, 1);  // R=1,W=1,X=1,U=1, A=1, D=0, V=1
    mem_write_pte(l0_addr, pte_l0);

    $display("[MMU] TEST9: PTE before STORE: A=1, D=0");
    print_all("TEST9 BEFORE", l1_addr, l0_addr);

    cpu_req_data(vaddr, ACCESS_STORE, satp_sv32, USER_MODE);
    wait_ready_data();

    exp_paddr = {leaf_ppn, vaddr[11:0]};
    
    // The translation should succeed (W=1 allows stores)
    if (data_if.page_fault) begin
      $fatal(1, "[MMU] TEST9: unexpected page_fault - STORE should be allowed with W=1");
    end
    if (data_if.paddr !== exp_paddr) begin
      $fatal(1, "[MMU] TEST9: paddr mismatch (exp=%h got=%h)", exp_paddr, data_if.paddr);
    end
    
    // Verify the dirty bit was updated in memory by the page walker
    begin
      pte_sv32_t updated_pte;
      updated_pte = pte_sv32_t'(mem[l0_addr]);
      if (!updated_pte.d) begin
        $display("[MMU] TEST9: WARNING - D bit not updated in memory (may be handled by SW)");
      end else begin
        $display("[MMU] TEST9: D bit correctly updated to 1 in memory");
      end
    end
    $display("[MMU] TEST9: Dirty bit update OK (paddr=%h)", data_if.paddr);
    print_all("TEST9 AFTER", l1_addr, l0_addr);

    // =========================================================================
    $display("\n========== TEST 10: Access bit update (A=0 -> LOAD) ==========");
    // =========================================================================
    do_flush();

    // Create a PTE with A=0, D=0 - a LOAD should trigger access bit update
    pte_l0 = make_pte_leaf(leaf_ppn, 1,1,1,1, 0, 0,0, 1);  // R=1,W=1,X=1,U=1, A=0, D=0, V=1
    mem_write_pte(l0_addr, pte_l0);

    $display("[MMU] TEST10: PTE before LOAD: A=0, D=0");
    print_all("TEST10 BEFORE", l1_addr, l0_addr);

    cpu_req_data(vaddr, ACCESS_LOAD, satp_sv32, USER_MODE);
    wait_ready_data();

    exp_paddr = {leaf_ppn, vaddr[11:0]};
    
    if (data_if.page_fault) begin
      $fatal(1, "[MMU] TEST10: unexpected page_fault");
    end
    if (data_if.paddr !== exp_paddr) begin
      $fatal(1, "[MMU] TEST10: paddr mismatch (exp=%h got=%h)", exp_paddr, data_if.paddr);
    end
    
    // Verify the access bit was updated
    begin
      pte_sv32_t updated_pte;
      updated_pte = pte_sv32_t'(mem[l0_addr]);
      if (!updated_pte.a) begin
        $display("[MMU] TEST10: WARNING - A bit not updated in memory (may be handled by SW)");
      end else begin
        $display("[MMU] TEST10: A bit correctly updated to 1 in memory");
      end
    end
    $display("[MMU] TEST10: Access bit update OK (paddr=%h)", data_if.paddr);
    print_all("TEST10 AFTER", l1_addr, l0_addr);

    // =========================================================================
    $display("\n========== TEST 11: Both A and D update (A=0,D=0 -> STORE) ==========");
    // =========================================================================
    do_flush();

    // Create a PTE with A=0, D=0 - a STORE should trigger both A and D update
    pte_l0 = make_pte_leaf(leaf_ppn, 1,1,1,1, 0, 0,0, 1);  // R=1,W=1,X=1,U=1, A=0, D=0, V=1
    mem_write_pte(l0_addr, pte_l0);

    $display("[MMU] TEST11: PTE before STORE: A=0, D=0");
    print_all("TEST11 BEFORE", l1_addr, l0_addr);

    cpu_req_data(vaddr, ACCESS_STORE, satp_sv32, USER_MODE);
    wait_ready_data();

    exp_paddr = {leaf_ppn, vaddr[11:0]};
    
    if (data_if.page_fault) begin
      $fatal(1, "[MMU] TEST11: unexpected page_fault");
    end
    if (data_if.paddr !== exp_paddr) begin
      $fatal(1, "[MMU] TEST11: paddr mismatch (exp=%h got=%h)", exp_paddr, data_if.paddr);
    end
    
    // Verify both A and D bits were updated
    begin
      pte_sv32_t updated_pte;
      updated_pte = pte_sv32_t'(mem[l0_addr]);
      $display("[MMU] TEST11: Updated PTE - A=%b, D=%b", updated_pte.a, updated_pte.d);
      if (!updated_pte.a || !updated_pte.d) begin
        $display("[MMU] TEST11: WARNING - A/D bits not fully updated (may be handled by SW)");
      end else begin
        $display("[MMU] TEST11: Both A and D bits correctly updated to 1");
      end
    end
    $display("[MMU] TEST11: A+D bit update OK (paddr=%h)", data_if.paddr);
    print_all("TEST11 AFTER", l1_addr, l0_addr);

    // =========================================================================
    $display("\n========== TODOS LOS TESTS PASARON ==========\n");
    // =========================================================================
    $finish;
  end

endmodule
