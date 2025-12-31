
interface mmu_pw_if;
  import pkg_virtual_memory::*;

  logic req;
  virtual_address_t vaddr;
  access_type_t access_type;
  satp_register_t satp;

  logic grant;  // if walker accepts the request
  logic done;  // if walker finishes the request
  tlb_entry_t entry;  // returned TLB entry
  logic fault;  // if page fault occurs

  modport mmu(
      output satp,
      output req,
      output vaddr,
      output access_type,
      input grant,
      input done,
      input entry,
      input fault
  );

  modport pw(
      input satp,
      input req,
      input vaddr,
      input access_type,
      output grant,
      output done,
      output entry,
      output fault
  );

endinterface : mmu_pw_if
