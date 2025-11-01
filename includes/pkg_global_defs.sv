`timescale 1ns / 1ps

import pkg_riscv_instructions::instruction_t;
import pkg_riscv_instructions::make_nop;

package pkg_global_defs;
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

    parameter TRUE = 1'b1;
    parameter FALSE = 1'b0;
    parameter IMM_32_WHATEVER = 32'h12345678;
    parameter REG_NR_INVALID_FALLBACK = 5'b00000;  // fallback to reading the zero register
    parameter INST_MEM_SIZE = 4096;
    parameter DATA_MEM_SIZE = 4096;

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
        // registers
        bool_t        isWriteback;
        // memory access
        bool_t        isStore;
        bool_t        isLoad;
        data_length_t stldDataLen;
        signedness_t  stldSignedness;
        // branching
        branch_type_t branchType;
    } inst_info_t;

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
        info.isWriteback = FALSE;
        info.isStore = FALSE;
        info.isLoad = FALSE;
        info.stldDataLen = DL_INVALID;
        info.stldSignedness = SS_INVALID;
        info.branchType = BR_INVALID;
    endfunction

    typedef struct {
        logic zero;
        logic negative;
        logic overflow;
        logic parity;
        logic carry;
    } alu_flags_t;

    typedef struct {
        bool_t illegalInstruction;
        bool_t illegalMemoryAccess;
        bool_t divideByZero;
    } exception_t;

    function automatic exception_t exception_make_none();
        exception_t exception;
        exception.illegalInstruction = FALSE;
        exception.illegalMemoryAccess = FALSE;
        exception.divideByZero = FALSE;
        return exception;
    endfunction

    typedef struct {
        bool_t halt;
        bool_t branchTaken;
        addr_t pcBr;
        exception_t exception;
    } if_control_t;

    typedef struct {
        reg_t pc;
        instruction_t inst;
        exception_t exceptions;
    } if_id_regs_t;

    typedef struct {
        bool_t WB_isWriteback;
        reg_nr_t WB_rd;
        word_t WB_rdData;
        bool_t WB_hasException;

        // register R/W conflict resolver
        reg_nr_t EX_rd;
        bool_t EX_isWriteback;
        bool_t EX_isLoad;  // If is load, the ALU result is the address not the register
        word_t EX_aluResult;

        reg_nr_t MEM_rd;
        bool_t   MEM_isWriteback;
        word_t   MEM_memResult;
    } id_control_t;

    typedef struct {
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
        bool_t EX_branchTaken;
        addr_t EX_pcBr;
        bool_t EX_isWriteback;
        reg_nr_t EX_rd;
        bool_t EX_isLoad;
        word_t EX_aluResult;
    } ex_hints_t;

    typedef struct {
        reg_t pc;
        inst_info_t instInfo;
        word_t aluResult;
        word_t stData;
        exception_t exceptions;
    } ex_mem_regs_t;

    typedef struct {bool_t placeholder;} mem_control_t;

    typedef struct {
        bool_t   shouldHalt;
        reg_nr_t MEM_rd;
        bool_t   MEM_isWriteback;
        word_t   MEM_memResult;
    } mem_hints_t;

    typedef struct {
        reg_t pc;
        inst_info_t instInfo;
        word_t memResult;
        exception_t exceptions;
    } mem_wb_regs_t;

    typedef struct {bool_t placeholder;} wb_control_t;

    typedef struct {
        bool_t   WB_isWriteback;
        reg_nr_t WB_rd;
        word_t   WB_rdData;
        bool_t WB_hasException;
        exception_t WB_exceptions;
    } wb_hints_t;


endpackage : pkg_global_defs
