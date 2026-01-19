`timescale 1ns / 1ps
`ifndef PKG_GLOBAL_DEFS_SV
`define PKG_GLOBAL_DEFS_SV

`include "rtl_common.svh"

`ifndef LESS_EXPRESSIVE_GRAMMAR
import pkg_riscv_instructions::*;
import pkg_virtual_memory::*;
package pkg_global_defs;
`endif
    // parameters
    parameter TRUE = 1'b1;
    parameter FALSE = 1'b0;
    parameter IMM_32_WHATEVER = 32'h12345678;
    parameter REG_NR_INVALID_FALLBACK = 5'b00000;  // fallback to reading the zero register
    parameter MEM_SIZE = 16 * 1024 * 1024;  // 16MB - practical limit for simulation
    parameter INST_MEM_SIZE = MEM_SIZE;
    parameter DATA_MEM_SIZE = MEM_SIZE;
    parameter START_ADDRESS = 'h1000;
    parameter ROB_TICKET_INVALID = 'hffffffff;

    // data types
    typedef logic clk_t;
    typedef logic bool_t;
    typedef logic [7:0] byte_t;
    typedef logic [15:0] half_t;
    typedef logic [31:0] word_t;
    typedef logic [4:0] reg_nr_t;
    typedef word_t imm_arith_t;
    typedef word_t addr_t;
    typedef word_t reg_t;
    // typedef byte_t [15:0] cacheline_data_t;
    typedef logic [127:0] cacheline_data_t;

    // instructions
    typedef enum logic [3:1] {
        BR_INVALID,
        BR_BEQ,
        BR_BNE,
        BR_BLT,
        BR_BGE,
        BR_BLTU,
        BR_BGEU,
        BR_UNCOND
    } branch_type_t;

    typedef enum logic [2:0] {
        DL_INVALID,
        DL_BYTE,
        DL_HALF,
        DL_WORD
    } data_length_t;

    typedef enum logic [1:0] {
        SS_INVALID,
        SS_SIGNED,
        SS_UNSIGNED
    } signedness_t;

    // ALU opcodes
    typedef enum logic [4:0] {
        ALU_INVALID,
        ALU_ADD,
        ALU_SUB,
        ALU_INC,
        ALU_DEC,
        ALU_NOT,
        ALU_AND,
        ALU_OR,
        ALU_XOR,
        ALU_SLL,
        ALU_SLT,
        ALU_SLTU,
        ALU_SRL,
        ALU_SRA
    } alu_op_t;

    typedef enum logic [1:0] {
        MEM_STLEN_INVALID,
        MEM_STLEN_BYTE,
        MEM_STLEN_HALF,
        MEM_STLEN_WORD
    } mem_stlen_t;

    // Comparator result
    typedef struct {
        bool_t eq;
        bool_t lt;
        bool_t gt;
    } cmp_result_t;

    typedef struct {
        reg_nr_t      rs1;
        reg_nr_t      rs2;
        reg_nr_t      rd;
        word_t        imm;
        // comparator
        bool_t        cmpIsSigned;
        // ALU
        alu_op_t      aluOp;
        bool_t        aluUseImmAsRs2;
        bool_t        aluUsePCAsRs1;
        // integer multiplication
        bool_t        isImul;
        // registers
        bool_t        isWriteback;
        // memory access
        bool_t        isStore;
        bool_t        isLoad;
        data_length_t stldDataLen;
        signedness_t  stldSignedness;
        // branching
        branch_type_t branchType;
`ifdef DEBUG_INST_INFO_EXTENSION
        instruction_t DEBUG_instBinary;
        word_t        DEBUG_instID;
        bool_t        DEBUG_isForcedNop;
`endif
    } inst_info_t;

    typedef struct {
        logic zero;
        logic negative;
        logic overflow;
        logic parity;
        logic carry;
    } alu_flags_t;

    typedef struct packed {
        bool_t illegalInstruction;
        bool_t illegalMemoryAccess;
        bool_t divideByZero;
    } exception_t;

    typedef struct {
        bool_t halt;
        bool_t WB_shouldJump;
        addr_t WB_jumpPC;
        exception_t exception;
        satp_register_t satp;
        priv_mode_t curr_priv_mode;
    } if_control_t;

    typedef struct {
        bool_t instValid;   // ID shold NOT insert into ROB if instruction is invalid
        reg_t pc;
        instruction_t inst;
        exception_t exceptions;
`ifdef DEBUG_INST_INFO_EXTENSION
        word_t DEBUG_instID;
`endif
    } if_id_regs_t;

    typedef struct {
        bool_t shouldHalt;
        bool_t IF_memRequestBusy;
    } if_hints_t;

    typedef struct {
        bool_t   halt;    // ID shuold not request ROB tickts on this signal
        bool_t   WB_isWriteback;
        reg_nr_t WB_rd;
        word_t   WB_rdData;
        bool_t   WB_hasException;
        bool_t   WB_shouldJump;
    } id_control_t;

    typedef struct {
        word_t ticket;
        reg_t pc;
        inst_info_t instInfo;
        exception_t exceptions;
        reg_t rs1Data;
        reg_t rs2Data;
    } id_ex_regs_t;

    typedef struct {
        bool_t shouldHalt;  // halt for data hazards
    } id_hints_t;

    typedef struct {bool_t placeholder;} ex_control_t;
    typedef struct {
        bool_t   shouldHalt;
        word_t   EX_ticket;
        exception_t EX_exceptions;
        // instruction types
        bool_t   EX_isWriteback;
        bool_t   EX_isLoad;
        bool_t   EX_isStore;
        bool_t   EX_isBranch;
        // branch instructions
        bool_t   EX_shouldBranch;
        addr_t   EX_branchPC;
        // store instruction
        word_t   EX_stData;

        // writeback instructions
        reg_nr_t EX_rd;
        // Rd or Virtual Address
        word_t   EX_aluResult;
        // Since we are using ROB, we don't need to halt, we just update the ROB entry
        // Old control logic (it should be handled by the WB stage instead)
        // When IF is not ready, halt until IF drained its cache requests
        // bool_t   shouldHalt;
    } ex_hints_t;

    typedef struct {
        word_t ticket;
        reg_t pc;
        inst_info_t instInfo;
        word_t aluResult;
        word_t stData;
        exception_t exceptions;
    } ex_mem_regs_t;

    typedef logic [8:0] asid_t;
    typedef struct packed {
        asid_t asid;
        addr_t va;
    } virt_addr_unique_t;

    typedef struct {
        // hints from ROB
        word_t ROB_commitTicket;
        bool_t ROB_commitIsStore;
        virt_addr_unique_t ROB_commitStVirtAddr;
        word_t ROB_commitStData;
        mem_stlen_t ROB_commitStLen;
        bool_t ROB_commitStoreComplete;
        satp_register_t satp;
        priv_mode_t currPrivMode;
    } mem_control_t;

    typedef struct {
        word_t ticket;
        bool_t shouldHalt;
        bool_t MEM_memRequestBusy;
        exception_t MEM_exceptions;
        // for load instructions
        bool_t MEM_pipeIsLoad;
        word_t MEM_pipeLoadData;  // should be available after memory access
        bool_t MEM_pipeLoadDataReady;
        // for oldest store instructions (commit write)
        word_t MEM_commitTicket;
        bool_t MEM_commitStoreComplete;
    } mem_hints_t;

    typedef struct {
        word_t ticket;
        reg_t pc;
        inst_info_t instInfo;
        word_t memResult;
        exception_t exceptions;
    } mem_wb_regs_t;

    typedef struct {
        bool_t shouldHalt;
        word_t WB_commitTicket;
        bool_t WB_commitFinished;
        bool_t WB_shouldJump;
        addr_t WB_jumpPC;
        bool_t WB_isWriteback;
        reg_nr_t WB_rd;
        word_t WB_rdData;
        bool_t WB_hasException;
    } wb_hints_t;

    typedef struct {
        // hints from IF stage
        bool_t IF_memRequestBusy;
        // hints from MEM stage
        bool_t MEM_memRequestBusy;
        // hints from ROB
        word_t ROB_commitTicket;
        exception_t ROB_commitException;
        // 1. register writeback commit
        bool_t ROB_commitIsWriteback;
        reg_nr_t ROB_commitRd;
        word_t ROB_commitRdData;
        // 2. non-writeback commit LOAD
        // check for memory access exceptions
        bool_t ROB_commitIsStore;
        bool_t ROB_commitStoreComplete;
        // 3. branch
        bool_t ROB_commitIsBranch;
        bool_t ROB_commitShouldBranch;
        addr_t ROB_commitBranchPCVirtAddr;
    } wb_control_t;

    typedef struct {
        bool_t WB_isWriteback;
        reg_nr_t WB_rd;
        word_t   EX_aluResult;
        // MEM -> ID bypass
        reg_nr_t MEM_rd;
        bool_t   MEM_isWriteback;
        word_t   MEM_memResult;
        // WB -> ID bypass
        bool_t   WB_isWriteback;
        reg_nr_t WB_rd;
        word_t   WB_rdData;
    } bypass_network_basic_info_t;

    typedef struct packed {
        bool_t isEmpty;
        bool_t isFull;
        // about the oldest entry
        word_t commitTicket;
        word_t commitPC;
        exception_t commitExceptions;
        bool_t commitIsWriteback;
        bool_t commitIsStore;
        bool_t commitIsBranch;
        // writeback (arithmetic / load)
        reg_nr_t commitRd;
        word_t commitRdData;
        // store
        virt_addr_unique_t commitStVirtAddr;
        word_t commitStData;
        mem_stlen_t commitStLen;
        bool_t commitStComplete;
        // branch
        bool_t commitShouldBranch;
        addr_t commitBranchPCVirtAddr;
    } rob_hints_t;

    typedef struct {
        // EX Stage (ALU)
        word_t EX_ticket;
        bool_t EX_isWriteback;
        bool_t EX_isLoad;
        bool_t EX_isStore;
        bool_t EX_isBranch;
        word_t EX_aluResult;
        word_t EX_branchPC;
        // branch instructions
        bool_t EX_shouldBranch;
        // ALU exceptions
        exception_t EX_exceptions;

        // MEM Stage (Assume serving one request per cycle)
        word_t MEM_ticket;  // surving ticket
        exception_t MEM_exceptions;  // exceptions
        virt_addr_unique_t MEM_virtAddr;
        // when serving load instructions
        bool_t MEM_isLoad;
        word_t MEM_loadData;
        bool_t MEM_loadDataReady;
        // when committing store instructions
        word_t MEM_commitTicket;
        bool_t MEM_commitStoreComplete;

        // INT-MUL Stage
        word_t IMUL_ticket;
        word_t IMUL_result;

        // WB stage
        // should not dequeue when the WB stage stops accepting/reaping commits
        word_t WB_commitTicket;
        bool_t WB_commitFinished;
        bool_t WB_shouldJump;
        // MEM stage
        // should not dequeue when MEM stage is stops accepting/reaping commits
        // bool_t MEM_acceptCommit;
        // NOTE: no need for this signal, since the receiver (ROB) can decide to dequeue when the mem stage set
        //       MEM_isCommitStore and MEM_commitStoreComplete signals
    } rob_control_t;

    typedef struct {
        word_t ticket;
        imm_arith_t A;
        imm_arith_t B;
    } id_imul_regs_t;

    typedef struct {
        bool_t flushPipeline;
    } imul_control_t;

    typedef struct {
        word_t IMUL_resultTicket;
        word_t IMUL_result;
    } imul_hints_t;

`ifndef LESS_EXPRESSIVE_GRAMMAR
    function automatic instruction_t inst_make_nop();
        instruction_t inst = make_nop();
        return inst;
    endfunction

    function automatic inst_info_t inst_info_make_nop();
        inst_info_t info;
        info.rs1 = REG_NR_INVALID_FALLBACK;
        info.rs2 = REG_NR_INVALID_FALLBACK;
        info.rd = REG_NR_INVALID_FALLBACK;
        info.imm = IMM_32_WHATEVER;
        info.cmpIsSigned = FALSE;
        info.aluOp = ALU_INVALID;
        info.aluUseImmAsRs2 = FALSE;
        info.isWriteback = TRUE;    // NOP writes back to Rd=0
        info.isStore = FALSE;
        info.isLoad = FALSE;
        info.stldDataLen = DL_INVALID;
        info.stldSignedness = SS_INVALID;
        info.branchType = BR_INVALID;
`ifdef DEBUG_INST_INFO_EXTENSION
        info.DEBUG_instBinary = inst_make_nop();
        // info.DEBUG_instID = '0;
        info.DEBUG_isForcedNop = TRUE;
`endif
        return info;
    endfunction

    // variant that preserves a provided DEBUG inst id (used when DEBUG_INST_INFO_EXTENSION is enabled)
    function automatic inst_info_t inst_info_make_nop_with_inst_id(input word_t debug_id);
        inst_info_t info = inst_info_make_nop();
`ifdef DEBUG_INST_INFO_EXTENSION
        info.DEBUG_instBinary = inst_make_nop();
        info.DEBUG_instID = debug_id;
        info.DEBUG_isForcedNop = TRUE;
`endif
        return info;
    endfunction

    function automatic exception_t exception_make_none();
        exception_t exception;
        exception.illegalInstruction = FALSE;
        exception.illegalMemoryAccess = FALSE;
        exception.divideByZero = FALSE;
        return exception;
    endfunction
`endif

`ifndef LESS_EXPRESSIVE_GRAMMAR
endpackage : pkg_global_defs
`endif
`endif
