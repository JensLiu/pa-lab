`timescale 1ns / 1ps

module page_walker
    import pkg_virtual_memory::*;
    import pkg_global_defs::*;
(
    input logic clk,
    input logic rst_n,

    // MMU Interface
    mmu_pw_if.page_walker   pw_mmu_if,
    // Page Walker Cache Interface
    pw_cache_if.page_walker pw_cache_if
);
    // Functions
    function automatic logic pte_is_leaf(input pte_sv32_t p);
        // Leaf si R o X
        return (p.r || p.x);
    endfunction

    function automatic permission_bits_t pte_to_perms(input pte_sv32_t p);
        permission_bits_t perms;
        perms.r = p.r;
        perms.w = p.w;
        perms.x = p.x;
        perms.u = p.u;
        perms.g = p.g;
        perms.a = p.a;
        perms.d = p.d;
        return perms;
    endfunction

    function automatic addr_t mk_pte_addr(input ppn_t base_ppn, input logic [9:0] idx);
        // base_ppn<<12 + idx*4 (PTE 4 bytes)
        addr_t base;
        base = {base_ppn, 12'b0};
        return base + {20'b0, {idx, 2'b00}};
    endfunction

    function automatic logic pte_invalid_form(input pte_sv32_t p);
        // RISC-V: W=1 con R=0 es inválido
        return (!p.r && p.w);
    endfunction


    // State machine states
    typedef enum logic [3:0] {
        IDLE,
        RD_L1,
        WAIT_L1,
        CHECK_L1,
        RD_L0,
        WAIT_L0,
        CHECK_L0,
        UPDATE_AD,
        WAIT_AD,
        RESP_OK,
        RESP_FAULT
    } pw_state_t;
    pw_state_t pw_state_q, pw_state_d;



    // Registers to hold request info
    satp_register_t satp_q, satp_d;
    vaddr_t vaddr_q, vaddr_d;
    access_type_t access_type_q, access_type_d;
    priv_mode_t curr_priv_mode_q, curr_priv_mode_d;
    logic update_ad_q, update_ad_d;
    logic set_a_q, set_a_d;
    logic set_d_q, set_d_d;

    pte_sv32_t pte_l1_q, pte_l0_q;

    logic [9:0] vpn1, vpn0;
    assign vpn1 = vaddr_q[31:22];
    assign vpn0 = vaddr_q[21:12];

    page_fault_t fault_cause;
    always_comb begin
        unique case (access_type_q)
            ACCESS_IFETCH: fault_cause = PAGE_FAULT_IFETCH;
            ACCESS_LOAD: fault_cause = PAGE_FAULT_LOAD;
            ACCESS_STORE: fault_cause = PAGE_FAULT_STORE;
            default: fault_cause = PAGE_FAULT_NONE;
        endcase
    end

    // Sequential logic for state and registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pw_state_q <= IDLE;
            satp_q <= '0;
            vaddr_q <= '0;
            access_type_q <= ACCESS_NONE;
            curr_priv_mode_q <= USER_MODE;
            update_ad_q <= 1'b0;
            set_a_q <= 1'b0;
            set_d_q <= 1'b0;
            pte_l1_q <= '0;
            pte_l0_q <= '0;
        end else begin
            pw_state_q <= pw_state_d;
            // accept request on IDLE state
            if (pw_state_q == IDLE && pw_mmu_if.req) begin
                satp_q <= pw_mmu_if.satp;
                vaddr_q <= pw_mmu_if.vaddr;
                access_type_q <= pw_mmu_if.access_type;
                curr_priv_mode_q <= pw_mmu_if.curr_priv_mode;
                update_ad_q <= pw_mmu_if.update_ad;
                set_a_q <= pw_mmu_if.set_a;
                set_d_q <= pw_mmu_if.set_d;
            end

            // capture PTEs when received from cache
            if (pw_state_q == WAIT_L1 && pw_cache_if.ready && !pw_cache_if.fault) begin
                pte_l1_q <= pte_sv32_t'(pw_cache_if.rdata);
            end

            if (pw_state_q == WAIT_L0 && pw_cache_if.ready && !pw_cache_if.fault) begin
                pte_l0_q <= pte_sv32_t'(pw_cache_if.rdata);
            end
        end
    end

    // combinational logic state transitions and outputs
    permission_bits_t perms_l0;
    logic need_wr_ad, need_set_a, need_set_d;
    pte_sv32_t pte_modified;
    pte_sv32_t pte_final;
    addr_t l1_pte_addr, l0_pte_addr;

    always_comb begin
        pw_state_d = pw_state_q;
        // default outputs
        // MMU outputs
        pw_mmu_if.ready = 1'b0;
        pw_mmu_if.busy = (pw_state_q != IDLE);
        pw_mmu_if.page_fault = 1'b0;
        pw_mmu_if.fault_cause = fault_cause;
        pw_mmu_if.ppn = '0;
        pw_mmu_if.perms = '0;
        pw_mmu_if.pte = '0;
        // Cache outputs
        pw_cache_if.req = 1'b0;
        pw_cache_if.addr = '0;
        pw_cache_if.wdata = '0;
        pw_cache_if.is_write = 1'b0;

        // Default values for combinational variables to avoid latches
        perms_l0 = '0;
        need_wr_ad = 1'b0;
        need_set_a = 1'b0;
        need_set_d = 1'b0;
        pte_modified = '0;
        pte_final = '0;
        l1_pte_addr = '0;
        l0_pte_addr = '0;

        perms_l0 = pte_to_perms(pte_l0_q);

        // determine if A/D bits need to be updated
        need_set_a = update_ad_q && set_a_q && !pte_l0_q.a;
        need_set_d = update_ad_q && set_d_q && (access_type_q == ACCESS_STORE) && !pte_l0_q.d;
        need_wr_ad = need_set_a || need_set_d;

        pte_modified = pte_l0_q;
        if (need_set_a) pte_modified.a = 1'b1;
        if (need_set_d) pte_modified.d = 1'b1;

        // address computation for page table walks
        l1_pte_addr = mk_pte_addr(satp_q.ppn, vpn1);
        l0_pte_addr = mk_pte_addr(pte_l1_q.ppn, vpn0);

        // state machine
        case (pw_state_q)
            IDLE: begin
                if (pw_mmu_if.req) begin
                    pw_state_d = RD_L1;
                end
            end

            // Read Level 1 PTE
            RD_L1: begin
                pw_cache_if.req = 1'b1;
                pw_cache_if.is_write = 1'b0;
                pw_cache_if.addr = l1_pte_addr;
                pw_state_d = WAIT_L1;
            end

            // Wait for L1 PTE response
            WAIT_L1: begin
                pw_cache_if.req = 1'b1;
                pw_cache_if.is_write = 1'b0;
                pw_cache_if.addr = l1_pte_addr;
                if (pw_cache_if.ready) begin
                    pw_state_d = pw_cache_if.fault ? RESP_FAULT : CHECK_L1;
                end
            end
            // Check L1 PTE
            CHECK_L1: begin
                if (pte_l1_q.no_used != 2'b00) begin
                    // Reserved bits set
                    pw_state_d = RESP_FAULT;
                end else if (!pte_l1_q.v) begin
                    // Invalid PTE
                    pw_state_d = RESP_FAULT;
                end else if (pte_invalid_form(pte_l1_q)) begin
                    // Invalid PTE form W=1 and R=0
                    pw_state_d = RESP_FAULT;
                end else if (!pte_is_leaf(pte_l1_q)) begin
                    // Non-leaf, go to L0
                    pw_state_d = RD_L0;
                end else begin
                    // Leaf PTE at L1 (superpage) - not supported in the designed scheme
                    pw_state_d = RESP_FAULT;
                end
            end

            // Read Level 0 PTE
            RD_L0: begin
                pw_cache_if.req = 1'b1;
                pw_cache_if.is_write = 1'b0;
                pw_cache_if.addr = l0_pte_addr;
                pw_state_d = WAIT_L0;
            end

            // Wait for L0 PTE response
            WAIT_L0: begin
                pw_cache_if.req = 1'b1;
                pw_cache_if.is_write = 1'b0;
                pw_cache_if.addr = l0_pte_addr;
                if (pw_cache_if.ready) begin
                    pw_state_d = pw_cache_if.fault ? RESP_FAULT : CHECK_L0;
                end
            end
            // Check L0 PTE
            CHECK_L0: begin
                if (pte_l0_q.no_used != 2'b00) begin
                    // Reserved bits set
                    pw_state_d = RESP_FAULT;
                end else if (!pte_l0_q.v) begin
                    // Invalid PTE
                    pw_state_d = RESP_FAULT;
                end else if (!pte_is_leaf(pte_l0_q)) begin
                    // Non-leaf at L0
                    pw_state_d = RESP_FAULT;
                end else if (pte_invalid_form(pte_l0_q)) begin
                    // Invalid PTE form W=1 and R=0
                    pw_state_d = RESP_FAULT;
                end else begin
                    // check permissions
                    if (access_type_q == ACCESS_IFETCH && !perms_l0.x) begin
                        pw_state_d = RESP_FAULT;
                    end else if (access_type_q == ACCESS_LOAD && !perms_l0.r) begin
                        pw_state_d = RESP_FAULT;
                    end else if (access_type_q == ACCESS_STORE && !perms_l0.w) begin
                        pw_state_d = RESP_FAULT;
                    end else if (curr_priv_mode_q == USER_MODE && !perms_l0.u) begin
                        pw_state_d = RESP_FAULT;
                    end else if (need_wr_ad) begin
                        pw_state_d = UPDATE_AD;
                    end else begin
                        pw_state_d = RESP_OK;
                    end
                end
            end
            // Update A/D bits in PTE
            UPDATE_AD: begin
                pw_cache_if.req = 1'b1;
                pw_cache_if.is_write = 1'b1;
                pw_cache_if.addr = l0_pte_addr;
                pw_cache_if.wdata = pte_modified;
                pw_state_d = WAIT_AD;
            end

            // Wait for A/D update completion
            WAIT_AD: begin
                pw_cache_if.req = 1'b1;
                pw_cache_if.is_write = 1'b1;
                pw_cache_if.addr = l0_pte_addr;
                pw_cache_if.wdata = pte_modified;
                if (pw_cache_if.ready) begin
                    pw_state_d = pw_cache_if.fault ? RESP_FAULT : RESP_OK;
                end
            end
            // Respond with success
            RESP_OK: begin
                pte_final = pte_l0_q;
                if (need_wr_ad) pte_final = pte_modified;

                pw_mmu_if.ready = 1'b1;
                pw_mmu_if.page_fault = 1'b0;
                pw_mmu_if.fault_cause = fault_cause;

                pw_mmu_if.ppn = pte_final.ppn;
                pw_mmu_if.perms = pte_to_perms(pte_final);
                pw_mmu_if.pte = pte_final;
                pw_state_d = IDLE;
            end

            // Respond with fault
            RESP_FAULT: begin
                pw_mmu_if.ready = 1'b1;
                pw_mmu_if.page_fault = 1'b1;
                pw_mmu_if.fault_cause = fault_cause;
                pw_mmu_if.ppn = '0;
                pw_mmu_if.perms = '0;
                pw_mmu_if.pte = '0;
                pw_state_d = IDLE;
            end
            default: begin
                pw_state_d = IDLE;
            end
        endcase
    end
endmodule : page_walker
