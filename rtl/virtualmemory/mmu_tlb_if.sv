interface mmu_tlb_if;
  import pkg_virtual_memory::*;

  logic req;
  virtual_address_t vaddr;
  access_type_t access_type;
  logic flush;
  logic update_entry;
  tlb_entry_t new_entry;

  logic [8:0] asid;  // Address Space Identifier

  logic hit;
  physical_address_t paddr;
  permission_t permission;

  modport mmu(
      output req,
      output vaddr,
      output access_type,
      input hit,
      input paddr,
      input permission,
      output flush,
      output update_entry,
      output new_entry,
      output asid
  );

  modport tlb(
      input req,
      input vaddr,
      input access_type,
      output hit,
      output paddr,
      output permission,
      input flush,
      input update_entry,
      input new_entry,
      input asid
  );


endinterface : mmu_tlb_if
