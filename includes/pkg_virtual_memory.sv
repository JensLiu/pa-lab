package pkg_virtual_memory;

  typedef logic [31:0] virtual_address_t;
  typedef logic [31:0] physical_address_t;

  typedef enum logic [1:0] {
    ACCESS_LOAD  = 2'b00,
    ACCESS_STORE = 2'b01,
    ACCESS_FETCH = 2'b10,
    ACCESS_NONE  = 2'b11
  } access_type_t;

  typedef struct packed {
    logic d;
    logic a;
    logic g;
    logic u;
    logic x;
    logic w;
    logic r;
  } permission_bits_t;

  typedef struct packed {
    logic [21:0] ppn;  // Physical Page Number
    logic [19:0] vpn;  // Virtual Page Number
    permission_bits_t perms;
    logic valid;
    logic [8:0] asid;  // Address Space Identifier
  } tlb_entry_t;

  typedef struct packed {
    logic mode;  // Addressing mode
    logic [8:0] asid;  // Address Space Identifier
    logic [21:0] ppn;  // Physical Page Number
  } satp_register_t;

  typedef struct packed {
    logic [9:0]  vpn2;
    logic [9:0]  vpn1;
    logic [11:0] page_offset;
  } virtual_address_t;

  typedef enum logic {
    USER_MODE,
    SUPERVISOR_MODE
  } priv_mode_t;

  typedef enum logc [2:0] {
    NO_VIOLATION,
    READ_VIOLATION,  // If no read permission
    WRITE_VIOLATION,  // If no write permission
    EXECUTE_VIOLATION,  // If no execute permission
    PRIVILEGE_VIOLATION  // If access mode is insufficient
  } permision_violation_t;

  typedef struct packed {
    logic perm_ok;
    permision_violation_t violation;
    logic need_set_a;
    logic need_set_d;
  } perm_check_result_t;

endpackage : pkg_virtual_memory
