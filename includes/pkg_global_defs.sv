`timescale 1ns / 1ps

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

    // Comparator result
    typedef struct {
        bool_t eq;
        bool_t lt;
        bool_t gt;
    } cmp_result_t;

    parameter TRUE = 1'b1;
    parameter FALSE = 1'b0;

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

    typedef struct {
        logic zero;
        logic negative;
        logic overflow;
        logic parity;
        logic carry;
    } alu_flags_t;

    parameter IMM_32_WHATEVER = 32'h12345678;
    parameter REG_NR_INVALID_FALLBACK = 5'b00000;  // fallback to reading the zero register
    parameter INST_MEM_SIZE = 4096;
    parameter DATA_MEM_SIZE = 4096;

endpackage : pkg_global_defs
