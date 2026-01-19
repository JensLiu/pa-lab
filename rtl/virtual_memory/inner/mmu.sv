`timescale 1ns / 1ps

module mmu
    import pkg_virtual_memory::*;
    import pkg_global_defs::*;
(
    input logic clk,
    input logic rst_n,
    // CPU Interface
    cpu_mmu_if.mmu instr_if,
    cpu_mmu_if.mmu data_if,
    // TLB Interface
    mmu_tlb_if.mmu i_tlb_if,
    mmu_tlb_if.mmu d_tlb_if,
    // Page Table Walker Interface
    mmu_pw_if.mmu ptw_if
);

    // bypass detection
    logic os_bypass_i, os_bypass_d;
    always_comb begin
        os_bypass_d = (data_if.satp.mode == SATP_MODE_BARE) || (data_if.curr_priv_mode == SUPERVISOR_MODE);
        os_bypass_i = (instr_if.satp.mode == SATP_MODE_BARE) || (instr_if.curr_priv_mode == SUPERVISOR_MODE);
    end

    // Two state machines, differenciating instruction and data TLB misses
    typedef enum logic [1:0] {
        IDLE,
        WAIT_PTW,
        RELOOKUP
    } mmu_channel_state_t;

    mmu_channel_state_t i_mmu_state_q, d_mmu_state_q;
    mmu_channel_state_t i_mmu_state_d, d_mmu_state_d;

    // Pending regs per channel
    vaddr_t i_vaddr_q, d_vaddr_q;
    access_type_t i_acc_q, d_acc_q;
    satp_register_t i_satp_q, d_satp_q;
    priv_mode_t i_priv_q, d_priv_q;
    // A/D update tracking per channel
    logic i_need_a_q, i_need_d_q;
    logic d_need_a_q, d_need_d_q;

    // PTW owner tracking
    typedef enum logic [1:0] {
        PTW_IDLE,
        PTW_I,
        PTW_D
    } ptw_owner_t;
    ptw_owner_t ptw_own_q, ptw_own_d;

    // TLB Fill signals
    // Instruction TLB fill
    logic i_fill_req;
    vpn_t i_fill_vpn;
    ppn_t i_fill_ppn;
    permission_bits_t i_fill_perm;
    satp_register_t i_fill_satp;
    // Data TLB fill
    logic d_fill_req;
    vpn_t d_fill_vpn;
    ppn_t d_fill_ppn;
    permission_bits_t d_fill_perm;
    satp_register_t d_fill_satp;

    // itlb lookup
    always_comb begin
        // Default signals
        i_tlb_if.lookup_req = 1'b0;
        i_tlb_if.lookup_vaddr = '0;
        i_tlb_if.lookup_access_type = ACCESS_IFETCH;
        i_tlb_if.lookup_satp = instr_if.satp;
        i_tlb_if.lookup_priv = instr_if.curr_priv_mode;

        i_tlb_if.fill_req = i_fill_req;
        i_tlb_if.fill_vpn = i_fill_vpn;
        i_tlb_if.fill_ppn = i_fill_ppn;
        i_tlb_if.fill_perm = i_fill_perm;
        i_tlb_if.fill_satp = i_fill_satp;

        i_tlb_if.flush_req = instr_if.flush;

        if (i_mmu_state_q == IDLE) begin
            if (instr_if.req && !os_bypass_i) begin
                i_tlb_if.lookup_req   = 1'b1;
                i_tlb_if.lookup_vaddr = instr_if.vaddr;
            end
        end else if (i_mmu_state_q == RELOOKUP) begin
            // Re-issue TLB lookup after PTW fill
            i_tlb_if.lookup_req = 1'b1;
            i_tlb_if.lookup_vaddr = i_vaddr_q;
            i_tlb_if.lookup_satp = i_satp_q;
            i_tlb_if.lookup_priv = i_priv_q;
            i_tlb_if.lookup_access_type = i_acc_q;
        end
    end

    // dtlb lookup
    always_comb begin
        // Default signals
        d_tlb_if.lookup_req = 1'b0;
        d_tlb_if.lookup_vaddr = '0;
        d_tlb_if.lookup_access_type = data_if.access_type;
        d_tlb_if.lookup_satp = data_if.satp;
        d_tlb_if.lookup_priv = data_if.curr_priv_mode;

        // Fill signals
        d_tlb_if.fill_req = d_fill_req;
        d_tlb_if.fill_vpn = d_fill_vpn;
        d_tlb_if.fill_ppn = d_fill_ppn;
        d_tlb_if.fill_perm = d_fill_perm;
        d_tlb_if.fill_satp = d_fill_satp;
        // Flush signal
        d_tlb_if.flush_req = data_if.flush;

        if (d_mmu_state_q == IDLE) begin
            if (data_if.req && !os_bypass_d) begin
                d_tlb_if.lookup_req   = 1'b1;
                d_tlb_if.lookup_vaddr = data_if.vaddr;
            end
        end else if (d_mmu_state_q == RELOOKUP) begin
            // Re-issue TLB lookup after PTW fill
            d_tlb_if.lookup_req = 1'b1;
            d_tlb_if.lookup_vaddr = d_vaddr_q;
            d_tlb_if.lookup_satp = d_satp_q;
            d_tlb_if.lookup_priv = d_priv_q;
            d_tlb_if.lookup_access_type = d_acc_q;
        end
    end

    // Lookup results
    logic i_valid, d_valid;
    logic i_hit, d_hit;
    logic i_miss, d_miss;
    logic i_need_ad_update, d_need_ad_update;
    always_comb begin
        i_valid = i_tlb_if.lookup_req && i_tlb_if.lookup_ready;
        d_valid = d_tlb_if.lookup_req && d_tlb_if.lookup_ready;

        i_hit = i_valid && i_tlb_if.hit;
        d_hit = d_valid && d_tlb_if.hit;

        i_miss = i_valid && !i_tlb_if.hit;
        d_miss = d_valid && !d_tlb_if.hit;

        i_need_ad_update = i_hit && !i_tlb_if.perm_fault && (i_tlb_if.need_a_update || i_tlb_if.need_d_update);
        d_need_ad_update = d_hit && !d_tlb_if.perm_fault && (d_tlb_if.need_a_update || d_tlb_if.need_d_update);
    end

    // MMU State Machines
    always_comb begin
        // Default next states
        i_mmu_state_d = i_mmu_state_q;
        d_mmu_state_d = d_mmu_state_q;

        unique case (i_mmu_state_q)
            IDLE: begin
                if (i_valid && !os_bypass_i && (i_miss || i_need_ad_update)) begin
                    // TLB miss or need A/D update, start PTW
                    i_mmu_state_d = WAIT_PTW;
                end
            end
            WAIT_PTW: begin
                if (ptw_if.ready && (ptw_own_q == PTW_I)) begin
                    if (ptw_if.page_fault) begin
                        // Page fault, go back to IDLE
                        i_mmu_state_d = IDLE;
                    end else begin
                        // Successful PTW, go to RELOOKUP
                        i_mmu_state_d = RELOOKUP;
                    end
                end
            end
            RELOOKUP: begin
                if (i_valid) begin
                    if (i_hit && !i_tlb_if.perm_fault &&
            !(i_tlb_if.need_a_update || i_tlb_if.need_d_update)) begin
                        // Successful re-lookup, back to IDLE
                        i_mmu_state_d = IDLE;
                    end else if (i_hit && i_tlb_if.perm_fault) begin
                        i_mmu_state_d = IDLE; // Permission fault, back to IDLE, deliver fault to CPU
                    end
                end
            end
            default: begin
                i_mmu_state_d = IDLE;
            end
        endcase

        unique case (d_mmu_state_q)
            IDLE: begin
                if (d_valid && !os_bypass_d && (d_miss || d_need_ad_update)) begin
                    // TLB miss or need A/D update, start PTW
                    d_mmu_state_d = WAIT_PTW;
                end
            end
            WAIT_PTW: begin
                if (ptw_if.ready && (ptw_own_q == PTW_D)) begin
                    if (ptw_if.page_fault) begin
                        // Page fault, go back to IDLE
                        d_mmu_state_d = IDLE;
                    end else begin
                        // Successful PTW, go to RELOOKUP
                        d_mmu_state_d = RELOOKUP;
                    end
                end
            end
            RELOOKUP: begin
                if (d_valid) begin
                    if (d_hit && !d_tlb_if.perm_fault &&
              !(d_tlb_if.need_a_update || d_tlb_if.need_d_update)) begin
                        // Successful re-lookup, back to IDLE
                        d_mmu_state_d = IDLE;
                    end else if (d_hit && d_tlb_if.perm_fault) begin
                        d_mmu_state_d = IDLE; // Permission fault, back to IDLE, deliver fault to CPU
                    end
                end
            end
            default: begin
                d_mmu_state_d = IDLE;
            end
        endcase
    end

    // when enter to WAIT_PTW state
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_mmu_state_q <= IDLE;
            d_mmu_state_q <= IDLE;

            ptw_own_q <= PTW_IDLE;
            // pending regs
            i_vaddr_q <= '0;
            i_acc_q <= ACCESS_IFETCH;
            i_satp_q <= '0;
            i_priv_q <= USER_MODE;

            d_vaddr_q <= '0;
            d_acc_q <= ACCESS_LOAD;
            d_satp_q <= '0;
            d_priv_q <= USER_MODE;

            i_need_a_q <= 1'b0;
            i_need_d_q <= 1'b0;
            d_need_a_q <= 1'b0;
            d_need_d_q <= 1'b0;

        end else begin
            i_mmu_state_q <= i_mmu_state_d;
            d_mmu_state_q <= d_mmu_state_d;
            // PTW owner tracking
            ptw_own_q <= ptw_own_d;

            // Capture pending regs on entering WAIT_PTW
            if (i_mmu_state_q == IDLE && i_mmu_state_d == WAIT_PTW) begin
                i_vaddr_q <= instr_if.vaddr;
                i_acc_q   <= ACCESS_IFETCH;
                i_satp_q  <= instr_if.satp;
                i_priv_q  <= instr_if.curr_priv_mode;
                i_need_a_q <= i_tlb_if.need_a_update;
                i_need_d_q <= i_tlb_if.need_d_update;
            end
            if (d_mmu_state_q == IDLE && d_mmu_state_d == WAIT_PTW) begin
                d_vaddr_q <= data_if.vaddr;
                d_acc_q   <= data_if.access_type;
                d_satp_q  <= data_if.satp;
                d_priv_q  <= data_if.curr_priv_mode;
                d_need_a_q <= d_tlb_if.need_a_update;
                d_need_d_q <= d_tlb_if.need_d_update;
            end
        end
    end

    // PTW arbitration and request signals
    logic ptw_req;
    ptw_owner_t ptw_own_selector;
    always_comb begin
        ptw_req = 1'b0;
        ptw_own_selector = ptw_own_q;

        // default PTW signals
        ptw_if.req = 1'b0;
        ptw_if.satp = '0;
        ptw_if.vaddr = '0;
        ptw_if.access_type = ACCESS_NONE;
        ptw_if.curr_priv_mode = USER_MODE;
        ptw_if.update_ad = 1'b0;
        ptw_if.set_a = 1'b0;
        ptw_if.set_d = 1'b0;

        // Use ptw_own_q to track if we've already sent a request (avoids combinational loop through ptw_if.ready)
        // Only send request if:
        // 1. Page walker is not busy (ptw_if.busy is registered in page_walker)
        // 2. We haven't already sent a request (ptw_own_q == PTW_IDLE)
        if (!ptw_if.busy && (ptw_own_q == PTW_IDLE)) begin
            if (d_mmu_state_q == WAIT_PTW) begin
                ptw_req = 1'b1;
                ptw_own_selector = PTW_D;

                ptw_if.req = 1'b1;
                ptw_if.satp = d_satp_q;
                ptw_if.vaddr = d_vaddr_q;
                ptw_if.access_type = d_acc_q;
                ptw_if.curr_priv_mode = d_priv_q;
                ptw_if.update_ad = d_need_a_q || d_need_d_q;
                ptw_if.set_a = d_need_a_q;
                ptw_if.set_d = d_need_d_q;

            end else if (i_mmu_state_q == WAIT_PTW) begin
                ptw_req = 1'b1;
                ptw_own_selector = PTW_I;

                ptw_if.req = 1'b1;
                ptw_if.satp = i_satp_q;
                ptw_if.vaddr = i_vaddr_q;
                ptw_if.access_type = i_acc_q;
                ptw_if.curr_priv_mode = i_priv_q;
                ptw_if.update_ad = i_need_a_q || i_need_d_q;
                ptw_if.set_a = i_need_a_q;
                ptw_if.set_d = i_need_d_q;

            end
        end
        // PTW owner tracking
        if (ptw_req) begin
            ptw_own_d = ptw_own_selector;
        end else if (ptw_if.ready) begin
            ptw_own_d = PTW_IDLE;
        end else begin
            ptw_own_d = ptw_own_q;
        end
    end

    // PTW response handling and TLB fill signals
    always_comb begin
        // Default fills
        i_fill_req  = 1'b0;
        i_fill_vpn  = '0;
        i_fill_ppn  = '0;
        i_fill_perm = '0;
        i_fill_satp = '0;
        d_fill_req  = 1'b0;
        d_fill_vpn  = '0;
        d_fill_ppn  = '0;
        d_fill_perm = '0;
        d_fill_satp = '0;

        // Handle PTW response
        if (ptw_if.ready && !ptw_if.page_fault) begin
            if (ptw_own_q == PTW_D && d_mmu_state_q == WAIT_PTW) begin
                // Data channel fill
                d_fill_req  = 1'b1;
                d_fill_vpn  = d_vaddr_q[31:12];
                d_fill_ppn  = ptw_if.ppn;
                d_fill_perm = ptw_if.perms;
                d_fill_satp = d_satp_q;
            end else if (ptw_own_q == PTW_I && i_mmu_state_q == WAIT_PTW) begin
                // Instruction channel fill
                i_fill_req  = 1'b1;
                i_fill_vpn  = i_vaddr_q[31:12];
                i_fill_ppn  = ptw_if.ppn;
                i_fill_perm = ptw_if.perms;
                i_fill_satp = i_satp_q;
            end

        end
    end

    // CPU response signals
    always_comb begin
        // default values
        instr_if.ready = 1'b0;
        instr_if.stall = 1'b0;
        instr_if.busy = 1'b0;
        instr_if.page_fault = 1'b0;
        instr_if.page_fault_cause = PAGE_FAULT_NONE;
        instr_if.paddr = '0;

        data_if.ready = 1'b0;
        data_if.stall = 1'b0;
        data_if.busy = 1'b0;
        data_if.page_fault = 1'b0;
        data_if.page_fault_cause = PAGE_FAULT_NONE;
        data_if.paddr = '0;

        // bypass case
        if (instr_if.req && os_bypass_i) begin
            instr_if.ready = 1'b1;
            instr_if.paddr = instr_if.vaddr;
        end

        if (data_if.req && os_bypass_d) begin
            data_if.ready = 1'b1;
            data_if.paddr = data_if.vaddr;
        end

        // stall management
        if (instr_if.req && !os_bypass_i && (i_mmu_state_q != IDLE)) begin
            instr_if.stall = 1'b1;
            instr_if.busy  = 1'b1;
        end
        if (data_if.req && !os_bypass_d && (d_mmu_state_q != IDLE)) begin
            data_if.stall = 1'b1;
            data_if.busy  = 1'b1;
        end

        // stall also on TLB miss and ad update
        if (instr_if.req && !os_bypass_i && (i_mmu_state_q == IDLE) && (i_miss || i_need_ad_update)) begin
            instr_if.stall = 1'b1;
            instr_if.busy  = 1'b1;
        end
        if (data_if.req && !os_bypass_d && (d_mmu_state_q == IDLE) && (d_miss || d_need_ad_update)) begin
            data_if.stall = 1'b1;
            data_if.busy  = 1'b1;
        end

        // Permission fault handling ON TLB HIT
        if (instr_if.req && !os_bypass_i && (i_mmu_state_q == IDLE) && i_hit && i_tlb_if.perm_fault) begin
            instr_if.ready = 1'b1;
            instr_if.page_fault = 1'b1;
            instr_if.page_fault_cause = PAGE_FAULT_IFETCH;
        end
        if (data_if.req && !os_bypass_d && (d_mmu_state_q == IDLE) && d_hit && d_tlb_if.perm_fault) begin
            data_if.ready = 1'b1;
            if (data_if.access_type == ACCESS_LOAD) begin
                data_if.page_fault_cause = PAGE_FAULT_LOAD;
            end else if (data_if.access_type == ACCESS_STORE) begin
                data_if.page_fault_cause = PAGE_FAULT_STORE;
            end
            data_if.page_fault = 1'b1;
        end

        // Successful TLB hit
        if (instr_if.req && !os_bypass_i && (i_mmu_state_q == IDLE) && i_hit && !i_tlb_if.perm_fault &&
          !(i_tlb_if.need_a_update || i_tlb_if.need_d_update)) begin
            instr_if.ready = 1'b1;
            instr_if.paddr = i_tlb_if.paddr;
        end
        if (data_if.req && !os_bypass_d && (d_mmu_state_q == IDLE) && d_hit && !d_tlb_if.perm_fault &&
          !(d_tlb_if.need_a_update || d_tlb_if.need_d_update)) begin
            data_if.ready = 1'b1;
            data_if.paddr = d_tlb_if.paddr;
        end

        // PTW page fault handling
        if (ptw_if.ready && ptw_if.page_fault) begin
            if (ptw_own_q == PTW_I) begin
                instr_if.page_fault = 1'b1;
                instr_if.page_fault_cause = ptw_if.fault_cause;
                instr_if.ready = 1'b1;
                instr_if.stall = 1'b0;
                instr_if.busy = 1'b0;
            end else if (ptw_own_q == PTW_D) begin
                data_if.page_fault = 1'b1;
                data_if.page_fault_cause = ptw_if.fault_cause;
                data_if.ready = 1'b1;
                data_if.stall = 1'b0;
                data_if.busy = 1'b0;
            end
        end

        // relookup handling
        if (i_mmu_state_q == RELOOKUP) begin
            if (i_valid) begin
                if (i_hit && !i_tlb_if.perm_fault &&
          !(i_tlb_if.need_a_update || i_tlb_if.need_d_update)) begin
                    instr_if.ready = 1'b1;
                    instr_if.paddr = i_tlb_if.paddr;
                    instr_if.stall = 1'b0;
                    instr_if.busy  = 1'b0;
                end else if (i_hit && i_tlb_if.perm_fault) begin
                    instr_if.page_fault = 1'b1;
                    instr_if.page_fault_cause = PAGE_FAULT_IFETCH;
                    instr_if.ready = 1'b1;
                    instr_if.stall = 1'b0;
                    instr_if.busy = 1'b0;
                end
            end
        end

        if (d_mmu_state_q == RELOOKUP) begin
            if (d_valid) begin
                if (d_hit && !d_tlb_if.perm_fault &&
            !(d_tlb_if.need_a_update || d_tlb_if.need_d_update)) begin
                    data_if.ready = 1'b1;
                    data_if.paddr = d_tlb_if.paddr;
                    data_if.stall = 1'b0;
                    data_if.busy  = 1'b0;
                end else if (d_hit && d_tlb_if.perm_fault) begin
                    data_if.page_fault = 1'b1;
                    if (d_acc_q == ACCESS_LOAD) begin
                        data_if.page_fault_cause = PAGE_FAULT_LOAD;
                    end else if (d_acc_q == ACCESS_STORE) begin
                        data_if.page_fault_cause = PAGE_FAULT_STORE;
                    end
                    data_if.ready = 1'b1;
                    data_if.stall = 1'b0;
                    data_if.busy  = 1'b0;
                end
            end
        end
    end


endmodule : mmu
