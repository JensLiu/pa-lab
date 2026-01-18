package pkg_virtual_memory;

  // ---------------- Basic address types ----------------
  typedef logic [31:0] vaddr_t;
  typedef logic [31:0] paddr_t;

  typedef logic [19:0] vpn_t;   // Sv32: 20-bit VPN (vpn1|vpn0)
  typedef logic [19:0] ppn_t;   // según tu PA / diseño

  // ---------------- Access type ----------------
  typedef enum logic [1:0] {
    ACCESS_LOAD   = 2'b00,
    ACCESS_STORE  = 2'b01,
    ACCESS_IFETCH = 2'b10,
    ACCESS_NONE   = 2'b11
  } access_type_t;

  // ---------------- Permission bits (TLB-level) ----------------
  typedef struct packed {
    logic d; // dirty 
    logic a; // accessed
    logic g; // global 
    logic u; // user
    logic x; // execute
    logic w; // write
    logic r; // read
  } permission_bits_t;

  // ---------------- TLB entry (hardware cache) ----------------
  typedef struct packed {
    ppn_t             ppn;
    vpn_t             vpn;
    permission_bits_t perms;
    logic             valid;  // TLB entry valid (internal)
    logic [8:0]       asid;
  } tlb_entry_t;

  // ---------------- SATP (simplified Sv32/BARE) ----------------
  typedef struct packed {
    logic       mode_sv32;   // 1=Sv32, 0=BARE (si simplificas)
    logic [8:0] asid;
    ppn_t       ppn;         // root page table PPN
  } satp_register_t;

  // ---------------- Virtual address decomposition (Sv32) ----------------
  typedef struct packed {
    logic [9:0]  vpn1;
    logic [9:0]  vpn0;
    logic [11:0] page_offset;
  } vaddr_fields_t;

  // ---------------- Privilege mode ----------------
  typedef enum logic [0:0] {
    USER_MODE       = 1'b0,
    SUPERVISOR_MODE = 1'b1
  } priv_mode_t;

  // ---------------- Permission check result ----------------
  typedef enum logic [2:0] {
    NO_VIOLATION,
    READ_VIOLATION,
    WRITE_VIOLATION,
    EXECUTE_VIOLATION,
    PRIVILEGE_VIOLATION
  } permission_violation_t;

  typedef struct packed {
    logic                  perm_ok;
    permission_violation_t violation;
    logic                  need_set_a;
    logic                  need_set_d;
  } perm_check_result_t;

  // ---------------- PTE ----------------
  typedef struct packed {
    logic [1:0] no_used;
    ppn_t  ppn;
    logic [1:0] rsw;
    logic  d, a, g, u, x, w, r, v; // v = present/valid in page table
  } pte_sv32_t;

  typedef enum logic [2:0] {
    PAGE_FAULT_NONE,
    PAGE_FAULT_LOAD,
    PAGE_FAULT_STORE,
    PAGE_FAULT_IFETCH
  } page_fault_t;

// functions to check permissions
function automatic perm_check_result_t check_permissions_and_ad(
  input permission_bits_t perms,
  input access_type_t access,
  input priv_mode_t curr_mode
);
  perm_check_result_t result;

  begin
    // Default values
    result = '0;
    result.perm_ok = 1'b1;
    result.violation = NO_VIOLATION;
    result.need_set_a = 1'b0;
    result.need_set_d = 1'b0;

    // Check user/supervisor mode
    if (perms.u == 1'b0 && curr_mode == USER_MODE) begin
      result.perm_ok = 1'b0;
      result.violation = PRIVILEGE_VIOLATION;
      return result;
    end

    // Check access type permissions
    case (access)
      ACCESS_LOAD: begin
        if (perms.r == 1'b0) begin
          result.perm_ok = 1'b0;
          result.violation = READ_VIOLATION;
          return result;
        end
      end
      ACCESS_STORE: begin
        if (perms.w == 1'b0) begin
          result.perm_ok = 1'b0;
          result.violation = WRITE_VIOLATION;
          return result;
        end
      end
      ACCESS_IFETCH: begin
        if (perms.x == 1'b0) begin
          result.perm_ok = 1'b0;
          result.violation = EXECUTE_VIOLATION;
          return result;
        end
      end
      default: begin
        // No access requested
        result.perm_ok = 1'b0;
        result.violation = NO_VIOLATION;
        return result;
      end
    endcase

    // Check and indicate if A/D bits need to be set
    if (perms.a == 1'b0) begin
      result.need_set_a = 1'b1;
    end
    if (perms.d == 1'b0 && access == ACCESS_STORE) begin
      result.need_set_d = 1'b1;
    end
    return result;
  end
endfunction : check_permissions_and_ad

endpackage : pkg_virtual_memory
