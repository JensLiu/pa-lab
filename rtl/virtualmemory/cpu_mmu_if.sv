interface cpu_mmu_if;

  import pkg_virtual_memory::*;
  import pkg_global_defs::*;

  logic req;
  virtual_address_t vaddr;
  access_type_t access_type;

  logic ready;
  physical_address_t paddr;
  logic page_fault;

  satp_register_t satp;
  logic busy;

  modport mmu(
      input satp,
      input req,
      input vaddr,
      input access_type,
      output ready,
      output paddr,
      output page_fault,
      output busy
  );

  modport cpu(
      output satp,
      output req,
      output vaddr,
      output access_type,
      input ready,
      input paddr,
      input page_fault,
      input busy
  );

endinterface : cpu_mmu_if
