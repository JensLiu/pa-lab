interface cpu_mmu_if;
    import pkg_virtual_memory::*;

    logic req;
    virtual_address_t vaddr;
    access_type_t access_type;
    satp_register_t satp;
    priv_mode_t curr_priv_mode;
    logic mmu_enable; // MMU enable signal
    logic flush;  // if TLB flush is requested
    logic stall;  // if CPU should stall due to MMU operation
    logic page_fault;
    page_fault_t page_fault_cause;
    phys_addr_t paddr;
    logic ready;  // MMU indicates translation is ready
    logic busy;   // MMU is busy processing a request

    modport cpu (
        output req,
        output vaddr,
        output access_type,
        output satp,
        output curr_priv_mode,
        output mmu_enable,
        output flush,
        input stall,
        input page_fault,
        input page_fault_cause,
        input paddr,
        input ready,
        input busy
    );
    modport mmu (
        input req,
        input vaddr,
        input access_type,
        input satp,
        input curr_priv_mode,
        input mmu_enable,
        input flush,
        output stall,
        output page_fault,
        output page_fault_cause,
        output paddr,
        output ready,
        output busy
    );

endinterface : cpu_mmu_if
