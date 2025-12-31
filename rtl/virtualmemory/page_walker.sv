`timescale 1ns / 1ps

module page_walker
  import pkg_virtual_memory::*;
  import pkg_global_defs::*;
(
    input logic clk,
    input logic rst_n,
    // MMU Interface
    mmu_pw_if.pw pw_mmu_if,

    // Cache Interface
    output address_t mem_addr_o,
    output logic mem_req_o,
    output logic is_write_o,
    output logic [31:0] mem_wdata_o,
    input logic mem_ready_i,
    input logic [31:0] mem_rdata_i

);


  typedef enum logic [3:0] {
    PW_IDLE,
    PW_REQ_L1,
    PW_WAIT_L1,
    PW_DECIDE_L1,
    PW_REQ_L0,
    PW_WAIT_L0,
    PW_DECIDE_L0,
    PW_UPDATE_TLB,
    PW_FAULT,
    PW_DONE
  } pw_state_t;

  pw_state_t current_state, next_state;
  address_t l1_entry_addr;
  address_t l0_entry_addr;
  address_t final_phys_addr;
  tlb_entry_t pte_entry_l1;
  tlb_entry_t pte_entry_l0;
  satp_register_t satp_reg;
  virtual_address_t vaddr;
  logic fault_flag;
  logic [33:0] full_addr;


  // State Register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= PW_IDLE;
      satp_reg <= '0;
      vaddr <= '0;
      fault_flag <= 1'b0;
      pte_entry_l0 <= '0;
      pte_entry_l1 <= '0;
      final_phys_addr <= '0;
    end else begin
      current_state <= next_state;
    end
  end

  always_ff @(posedge clk) begin
    if (current_state == PW_IDLE) begin
      if (pw_mmu_if.req) begin
        satp_reg <= pw_mmu_if.satp;
        vaddr <= pw_mmu_if.vaddr;
      end
    end else if (current_state == PW_WAIT_L1 && mem_ready_i) begin
      pte_entry_l1 <= tlb_entry_t'(mem_rdata_i);
    end else if (current_state == PW_WAIT_L0 && mem_ready_i) begin
      pte_entry_l0 <= tlb_entry_t'(mem_rdata_i);
    end else if (current_state == PW_UPDATE_TLB && mem_ready_i) begin
      pte_entry_l0.a <= 1'b1;  // Set accessed bit
      if (pw_mmu_if.access_type == ACCESS_STORE) begin
        pte_entry_l0.d <= 1'b1;  // Set dirty bit on store
      end
    end
  end

  // Next State Logic
  always_comb begin
    next_state = current_state;
    mem_req_o = 1'b0;
    mem_addr_o = '0;
    is_write_o = 1'b0;
    mem_wdata_o = '0;
    pw_mmu_if.grant = 1'b0;  // maybe not needed
    pw_mmu_if.done = 1'b0;
    pw_mmu_if.entry = '0;
    pw_mmu_if.fault = 1'b0;

    tlb_entry_t modified_entry;
    modified_entry = pte_entry_l0;

    full_addr = '0;

    case (current_state)
      PW_IDLE: begin
        if (pw_mmu_if.req) begin
          next_state = PW_REQ_L1;
          pw_mmu_if.grant = 1'b1;
        end else begin
          next_state = PW_IDLE;
        end
      end

      PW_REQ_L1: begin
        mem_req_o  = 1'b1;
        is_write_o = 1'b0;  // Read operation
        full_addr  = {satp_reg.ppn, 12'b0} + {vaddr.vpn2, 2'b00};
        mem_addr_o = full_addr[31:0];  // only want 32bits, out machine now only supports up to 4GB
        next_state = PW_WAIT_L1;
      end
      PW_WAIT_L1: begin
        mem_req_o  = 1'b1;
        is_write_o = 1'b0;
        full_addr  = {satp_reg.ppn, 12'b0} + {vaddr.vpn2, 2'b00};
        mem_addr_o = full_addr[31:0];
        if (mem_ready_i) begin
          next_state = PW_DECIDE_L1;
          mem_req_o  = 1'b0;
        end
      end
      PW_DECIDE_L1: begin
        if (!pte_entry_l1.valid) begin
          next_state = PW_FAULT;
        end else if (!pte_entry_l1.perms.r && !pte_entry_l1.perms.w && !pte_entry_l1.perms.x) begin
          // Non-leaf PTE
          next_state = PW_REQ_L0;
        end else begin
          // Leaf PTE at L1
          // MEGA PAGE?? // not handled
          next_state = PW_DONE;
        end
      end

      PW_REQ_L0: begin
        mem_req_o  = 1'b1;
        is_write_o = 1'b0;  // Read operation
        full_addr  = {pte_entry_l1.ppn, 12'b0} + {vaddr.vpn1, 2'b00};
        mem_addr_o = full_addr[31:0];
        next_state = PW_WAIT_L0;
      end
      PW_WAIT_L0: begin
        mem_req_o  = 1'b1;
        is_write_o = 1'b0;
        full_addr  = {pte_entry_l1.ppn, 12'b0} + {vaddr.vpn1, 2'b00};
        mem_addr_o = full_addr[31:0];
        if (mem_ready_i) begin
          next_state = PW_DECIDE_L0;
          mem_req_o  = 1'b0;
        end
      end
      PW_DECIDE_L0: begin
        if (!pte_entry_l0.valid) begin
          next_state = PW_FAULT;
        end

        logic need_update;
        logic is_store_op;
        is_store_op = (pw_mmu_if.access_type == ACCESS_STORE);
        need_update = (is_store_op && !pte_entry_l0.perms.d) || (!pte_entry_l0.perms.a);

        if (need_update) begin
          next_state = PW_UPDATE_TLB;
        end else begin
          next_state = PW_DONE;
        end
      end
      PW_UPDATE_TLB: begin
        mem_req_o = 1'b1;
        is_write_o = 1'b1;  // Write operation
        full_addr = {pte_entry_l1.ppn, 12'b0} + {vaddr.vpn1, 2'b00};
        mem_addr_o = full_addr[31:0];

        modified_entry.a = 1'b1;
        if (pw_mmu_if.access_type == ACCESS_STORE) begin
          modified_entry.d = 1'b1;  // Set dirty bit on store
        end

        mem_wdata_o = tlb_entry_t'(modified_entry);
        if (mem_ready_i) begin
          next_state = PW_DONE;
          mem_req_o  = 1'b0;
          is_write_o = 1'b0;
        end else begin
          next_state = PW_UPDATE_TLB;
        end
      end

      PW_FAULT: begin
        pw_mmu_if.fault = 1'b1;
        pw_mmu_if.done = 1'b1;
        next_state = PW_IDLE;
      end

      PW_DONE: begin
        pw_mmu_if.entry = pte_entry_l0;
        pw_mmu_if.done = 1'b1;
        next_state = PW_IDLE;
      end
    endcase
  end

endmodule : page_walker
