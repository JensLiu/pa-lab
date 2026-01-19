// MMU and Page Walker interface
// 

interface mmu_pw_if;
  import pkg_virtual_memory::*;

  // ---------------- Request ----------------
  logic           req;            // start walk (level)
  satp_register_t satp;
  vaddr_t         vaddr;          // 32-bit VA bus
  access_type_t   access_type;    // IFETCH/LOAD/STORE
  priv_mode_t     curr_priv_mode;

  logic           update_ad;
  logic           set_a;
  logic           set_d;

  // ---------------- Response ----------------
  logic           ready;          // response valid (success or fault)
  logic           busy;           // walker in progress

  // Success payload
  ppn_t             ppn;
  permission_bits_t perms;
  pte_sv32_t        pte;          // optional/debug: leaf PTE

  // Fault classification
  logic           page_fault;     // V=0 => trap SO
  page_fault_t    fault_cause;    // LOAD/STORE/IFETCH (valid if page_fault=1)

  modport mmu (
    // output ports
    output req,
    output satp,
    output vaddr,
    output access_type,
    output curr_priv_mode,
    output update_ad,
    output set_a,
    output set_d,
    // input ports
    input  ready,
    input  busy,
    input  ppn,
    input  perms,
    input  pte,
    input  page_fault,
    input  fault_cause
  );

  modport page_walker (
    // input ports
    input  req,
    input  satp,
    input  vaddr,
    input  access_type,
    input  curr_priv_mode,
    input  update_ad,
    input  set_a,
    input  set_d,
    // output ports
    output ready,
    output busy,
    output ppn,
    output perms,
    output pte,
    output page_fault,
    output fault_cause
  );

endinterface : mmu_pw_if
