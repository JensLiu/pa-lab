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

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      entry_count <= 2'b00;
      foreach (tlb_entries[i]) begin
        tlb_entries[i].valid <= 1'b0;
      end
    end else if (tlb_mmu_if.flush) begin
      entry_count <= 2'b00;
      foreach (tlb_entries[i]) begin
        tlb_entries[i].valid <= 1'b0;
      end
    end else begin
      if (tlb_mmu_if.update_entry) begin
        tlb_entries[entry_count] <= tlb_mmu_if.new_entry;
        tlb_entries[entry_count].valid <= 1'b1;
        entry_count <= entry_count + 1;  // round-robin replacement
      end
    end
  end

  always_comb begin
    tlb_mmu_if.hit = 1'b0;
    tlb_mmu_if.paddr = '0;
    tlb_mmu_if.permission = '0;

    if (tlb_mmu_if.req) begin
      foreach (tlb_entries[i]) begin
        if (tlb_entries[i].valid && tlb_entries[i].vpn == tlb_mmu_if.vaddr[31:12]
            && (tlb_entries[i].asid == tlb_mmu_if.asid || tlb_entries[i].perms.g)
          ) begin
          tlb_mmu_if.hit = 1'b1;
          tlb_mmu_if.paddr = {tlb_entries[i].ppn, tlb_mmu_if.vaddr[11:0]};
          tlb_mmu_if.permission = tlb_entries[i].perms;
          break;
        end
      end
    end
  end

endmodule : tlb
