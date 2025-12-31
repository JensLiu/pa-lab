`timescale 1ns / 1ps

module mmu
  import pkg_virtual_memory::*;
  import pkg_global_defs::*;
(
    input logic clk,
    input logic rst_n,
    input satp_register_t satp,
    input priv_mode_t curr_priv_mode,
    // CPU Interface
    cpu_mmu_if.mmu instr_if,
    cpu_mmu_if.mmu data_if,
    // TLB Interface
    mmu_tlb_if.mmu i_tlb_if,
    mmu_tlb_if.mmu d_tlb_if,
    // Page Table Walker Interface
    mmu_ptw_if.mmu ptw_mmu_if
);

  // Function to check permissions
  function automatic logic check_page_permissions(
      input permissions_t perms, input access_type_t access_type, input priv_mode_t priv_mode);

    // Implement permission checking logic here
    // For simplicity, let's assume all accesses are allowed
    perm_check_result_t result;

    result.perm_ok = 1'b1;
    result.violation = NO_VIOLATION;
    result.need_set_a = 1'b0;
    result.need_set_d = 1'b0;

    if (priv_mode == USER_MODE && !perms.u) begin
      res.perm_ok = 1'b0;
      result.violation = PRIVILEGE_VIOLATION;
      return result;
    end

    case (access_type)
      ACCESS_FETCH: begin
        if (!perms.x) begin
          result.perm_ok   = 1'b0;
          result.violation = EXECUTE_VIOLATION;
        end
      end
      ACCESS_LOAD: begin
        if (!perms.r) begin
          result.perm_ok   = 1'b0;
          result.violation = READ_VIOLATION;
        end
      end
      ACCESS_STORE: begin
        if (!perms.w) begin
          result.perm_ok   = 1'b0;
          result.violation = WRITE_VIOLATION;
        end
      end
      default: begin
        result.perm_ok   = 1'b1;
        result.violation = NO_VIOLATION;
      end
    endcase

    if (!res.perm_ok) begin
      return result;
    end

    if (!perms.a) begin
      result.need_set_a = 1'b1;
    end

    if (access_type == ACCESS_STORE && !perms.d) begin
      result.need_set_d = 1'b1;
    end

    return result;
  endfunction : check_page_permissions


  typedef enum logic [1:0] {
    MMU_IDLE,
    MMU_WAIT_PW,
    MMU_FAULT,
    MMU_DONE
  } mmu_state_t;

  mmu_state_t curr_state, next_state;
  perm_check_result_t perm_check_res;
  // CPU Interface Signals
  phys_addr_t instr_phys_addr;
  phys_addr_t data_phys_addr;
  logic instr_fault, data_fault;
  logic instr_ready, data_ready;
  logic instr_busy, data_busy;

  assign instr_if.paddr = instr_phys_addr;
  assign data_if.paddr = data_phys_addr;
  assign instr_if.page_fault = instr_fault;
  assign data_if.page_fault = data_fault;
  assign instr_if.ready = instr_ready;
  assign data_if.ready = data_ready;
  assign instr_if.busy = instr_busy;
  assign data_if.busy = data_busy;

  // TLB Interface Signals
  logic i_tlb_req, d_tlb_req;
  virtual_address_t i_tlb_vaddr, d_tlb_vaddr;
  access_type_t i_tlb_access_type, d_tlb_access_type;
  logic i_tlb_flush, d_tlb_flush;
  tlb_entry_t i_tlb_entry_new, d_tlb_entry_new;
  logic [8:0] i_tlb_asid, d_tlb_asid;
  assign i_tlb_if.req = i_tlb_req;
  assign i_tlb_if.vaddr = i_tlb_vaddr;
  assign i_tlb_if.access_type = i_tlb_access_type;
  assign i_tlb_if.flush = i_tlb_flush;
  assign i_tlb_if.update_entry = 1'b0;  // TODO: Update Entry not implemented yet
  assign i_tlb_if.new_entry = i_tlb_entry_new;
  assign i_tlb_if.asid = i_tlb_asid;

  assign d_tlb_if.req = d_tlb_req;
  assign d_tlb_if.vaddr = d_tlb_vaddr;
  assign d_tlb_if.access_type = d_tlb_access_type;
  assign d_tlb_if.flush = d_tlb_flush;
  assign d_tlb_if.update_entry = 1'b0;  // TODO: Update Entry not implemented yet
  assign d_tlb_if.new_entry = d_tlb_entry_new;
  assign d_tlb_if.asid = d_tlb_asid;
  // ..................................

  // TODO: Flush and ASID handling not implemented yet

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      curr_state <= MMU_IDLE;
      next_state <= MMU_IDLE;
    end else begin
      curr_state <= next_state;
    end
  end

  always_comb begin
    next_state = curr_state;
    instr_phys_addr = '0;
    data_phys_addr = '0;
    case (curr_state)
      MMU_IDLE: begin
        if (satp.mode && (instr_if.req || data_if.req)) begin
          if (instr_if.req) begin
            // TODO: Handle instruction fetch
            i_tlb_req = 1'b1;
            i_tlb_vaddr = instr_if.vaddr;
            i_tlb_access_type = instr_if.access_type;

            if (i_tlb_if.hit && !i_tlb_if.page_fault) begin
              phys_addr_t   pa = i_tlb_if.paddr;
              permissions_t perms = i_tlb_if.permission;
              perm_check_res = check_page_permissions(perms, instr_if.access_type, curr_priv_mode);
              //TODO : Complete the logic here
              // if permissions are okay and accessed bit and dirty bit not needed to be set
              // then return physical address 


              // if permisions are okay but accessed bit or dirty bit need to be set
              // then send request to PTW to set the bits


              // if permissions are not okay then raise page fault

            end

          end

          if (data_if.req) begin
            // TODO: Handle data access
            d_tlb_if.req = 1'b1;
            d_tlb_if.vaddr = data_if.vaddr;
            d_tlb_if.access_type = data_if.access_type;
          end
        end  // Handle Bare Mode if no translation is required
        else if (!satp.mode && (instr_if.req || data_if.req)) begin
          if (instr_if.req) begin
            instr_phys_addr = phys_addr_t'(instr_if.vaddr);
            instr_if.ready = 1'b1;
            instr_if.page_fault = 1'b0;
          end
          if (data_if.req) begin
            data_phys_addr = phys_addr_t'(data_if.vaddr);
            data_if.ready = 1'b1;
            data_if.page_fault = 1'b0;
          end
        end else begin
          next_state = MMU_IDLE;
        end
      end
    endcase
  end


endmodule : mmu
