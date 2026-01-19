module tlb
  import pkg_virtual_memory::*;
  import pkg_global_defs::*;
(
    input logic clk,
    input logic rst_n,

    // MMU Interface
    mmu_tlb_if.tlb tlb_mmu_if

    // Cache Interface

);

  tlb_entry_t tlb_entries[4];  // 4-entry TLB
  logic [1:0] entry_count;
  perm_check_result_t perm_check_result;
  logic found;
  int hit_index;


  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // reset TLB entries
      entry_count <= 2'b00;
      foreach (tlb_entries[i]) begin
        tlb_entries[i].valid <= 1'b0;
      end
    end else if (tlb_mmu_if.flush_req) begin
      entry_count <= 2'b00;
      // invalidate all TLB entries
      foreach (tlb_entries[i]) begin
        tlb_entries[i].valid <= 1'b0;
      end
    end else begin
      if (tlb_mmu_if.fill_req) begin
        // Fill new TLB entry (simple round-robin replacement)
        if (found) begin
          // Update existing entry
          tlb_entries[hit_index].ppn <= tlb_mmu_if.fill_ppn;
          tlb_entries[hit_index].perms <= tlb_mmu_if.fill_perm;
          tlb_entries[hit_index].valid <= 1'b1;
        end else begin
          // Insert new entry
          tlb_entries[entry_count].vpn <= tlb_mmu_if.fill_vpn;
          tlb_entries[entry_count].ppn <= tlb_mmu_if.fill_ppn;
          tlb_entries[entry_count].perms <= tlb_mmu_if.fill_perm;
          tlb_entries[entry_count].valid <= 1'b1;
          tlb_entries[entry_count].asid <= tlb_mmu_if.fill_satp.asid;
          entry_count <= entry_count + 2'd1;  // round-robin replacement
        end
      end
    end
  end

  always_comb begin
    tlb_mmu_if.hit = 1'b0;
    tlb_mmu_if.paddr = '0;
    //tlb_mmu_if.permission = '0;
    perm_check_result = '0;
    tlb_mmu_if.lookup_ready = 1'b0;
    tlb_mmu_if.perm_fault = 1'b0;
    tlb_mmu_if.perm_violation = NO_VIOLATION;
    tlb_mmu_if.need_a_update = 1'b0;
    tlb_mmu_if.need_d_update = 1'b0;

    found = 1'b0;
    hit_index = -1;

    if (tlb_mmu_if.lookup_req && !tlb_mmu_if.flush_req) begin
      tlb_mmu_if.lookup_ready = 1'b1;
      foreach (tlb_entries[i]) begin
        if (tlb_entries[i].valid && tlb_entries[i].vpn == tlb_mmu_if.lookup_vaddr[31:12]
            && (tlb_entries[i].asid == tlb_mmu_if.lookup_satp.asid || tlb_entries[i].perms.g)
          ) begin
          tlb_mmu_if.hit = 1'b1;

          tlb_mmu_if.paddr = {tlb_entries[i].ppn, tlb_mmu_if.lookup_vaddr[11:0]};
          //tlb_mmu_if.permission = tlb_entries[i].perms;
          // Permission check
          perm_check_result = check_permissions_and_ad(
            tlb_entries[i].perms,
            tlb_mmu_if.lookup_access_type,
            tlb_mmu_if.lookup_priv
          );
          tlb_mmu_if.perm_fault = !perm_check_result.perm_ok;
          tlb_mmu_if.perm_violation = perm_check_result.violation;
          tlb_mmu_if.need_a_update = perm_check_result.need_set_a;
          tlb_mmu_if.need_d_update = perm_check_result.need_set_d;
          break;
        end
      end
    end

    if (tlb_mmu_if.fill_req) begin
      // No combinational outputs for fill
      for (int i = 0; i < 4; i++) begin
        if (tlb_entries[i].valid && tlb_entries[i].vpn == tlb_mmu_if.fill_vpn
            && (tlb_entries[i].asid == tlb_mmu_if.fill_satp.asid || tlb_entries[i].perms.g)
          ) begin
          found = 1'b1;
          hit_index = i;
          break;
        end
      end
    end

  end

endmodule : tlb
