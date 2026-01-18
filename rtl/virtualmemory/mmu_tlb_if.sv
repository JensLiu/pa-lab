interface mmu_tlb_if;
  import pkg_virtual_memory::*;

  // ---------------- Lookup request ----------------
  logic              lookup_req;            // start lookup
  vaddr_t            lookup_vaddr;
  access_type_t      lookup_access_type;   // LOAD / STORE / IFETCH / NONE
  satp_register_t    lookup_satp;
  priv_mode_t        lookup_priv;

  // ---------------- Lookup response ----------------
  logic              lookup_ready;          // response valid this cycle
  logic              hit;                   // 1 if entry found
  paddr_t            paddr;                 // valid if hit && !faults
  logic              perm_fault;            // R/W/X/U violation on hit
  permission_violation_t perm_violation;    // detailed violation info
  logic              need_a_update;        // hit but A=0 or (STORE && D=0)
  logic              need_d_update;


  // ---------------- Fill from page walker ----------------
  logic              fill_req;              // fill TLB entry
  vpn_t              fill_vpn;              // or virtual_address_t aligned to page
  ppn_t              fill_ppn;
  permission_bits_t   fill_perm;             // {R,W,X,U,A,D} bits
  satp_register_t    fill_satp;

  // ---------------- Flush / Invalidate ----------------
  logic              flush_req;             // start flush all

  modport mmu (
    // Output ports
    output lookup_req,
    output lookup_vaddr,
    output lookup_access_type,
    output lookup_satp,
    output lookup_priv,
    output fill_req,
    output fill_vpn,
    output fill_ppn,
    output fill_perm,
    output fill_satp,
    output flush_req,
    // Input ports
    input lookup_ready,
    input hit,
    input paddr,
    input perm_fault,
    input perm_violation,
    input need_a_update,
    input need_d_update
  );

  modport tlb (
    // Input ports
    input lookup_req,
    input lookup_vaddr,
    input lookup_access_type,
    input lookup_satp,
    input lookup_priv,
    input fill_req,
    input fill_vpn,
    input fill_ppn,
    input fill_perm,
    input fill_satp,
    input flush_req,
    // Output ports
    output lookup_ready,
    output hit,
    output paddr,
    output perm_fault,
    output perm_violation,
    output need_a_update,
    output need_d_update
  );

endinterface : mmu_tlb_if
