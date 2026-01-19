`timescale 1ns / 1ps
// riscv instructions

// reference
//  - https://danielmangum.com/posts/risc-v-bytes-intro-instruction-formats

`ifndef PKG_RISCV_INSTRUCTIONS_SV
`define PKG_RISCV_INSTRUCTIONS_SV

`ifndef LESS_EXPRESSIVE_GRAMMAR
package pkg_riscv_instructions;
`endif

    typedef enum logic [6:0] {
        OP_ALU_R =  7'b0110011,  // ALU: register-register
        OP_ALU_I =  7'b0010011,  // ALU: register-immediate
        OP_LD    =  7'b0000011,
        OP_ST    =  7'b0100011,
        OP_BR    =  7'b1100011,
        OP_LUI   =  7'b0110111,
        OP_JAL   =  7'b1101111,
        OP_JALR  =  7'b1100111
    } inst_opcode_t;

    typedef enum logic [2:0] {
        FN3_ADD_SUB = 3'b000,
        FN3_SLL     = 3'b001,
        FN3_SLT     = 3'b010,
        FN3_SLTU    = 3'b011,
        FN3_XOR     = 3'b100,
        FN3_SRL_SRA = 3'b101,
        FN3_OR      = 3'b110,
        FN3_AND     = 3'b111
    } inst_funct3_alu_t;

    typedef enum logic [2:0] {
        FN3_BYTE   = 3'b000,
        FN3_HALF   = 3'b001,
        FN3_WORD   = 3'b010,
        FN3_BYTE_U = 3'b100,
        FN3_HALF_U = 3'b101
    } inst_func3_ldst_t;

    typedef enum logic [2:0] {
        FN3_BEQ  = 3'b000,
        FN3_BNE  = 3'b001,
        FN3_BLT  = 3'b100,
        FN3_BGE  = 3'b101,
        FN3_BLTU = 3'b110,
        FN3_BGEU = 3'b111
    } inst_funct3_br_t;

    typedef enum logic [6:0] {
        FN7_ADD_SRL = 7'b0000000,
        FN7_SUB_SRA = 7'b0100000
    } inst_funct7_alu_t;

    typedef struct packed {
        logic [31:25] funct7;
        logic [24:20] rs2;
        logic [19:15] rs1;
        logic [14:12] funct3;
        logic [11:7]  rd;
        logic [6:0]   opcode;
    } instruction_generic_t;

    typedef struct packed {
        logic [31:25] funct7;
        logic [24:20] rs2;
        logic [19:15] rs1;
        logic [14:12] funct3;
        logic [11:7]  rd;
        logic [6:0]   opcode;
    } instruction_rtype_t;

    typedef struct packed {
        logic [31:20] imm;
        logic [19:15] rs1;
        logic [14:12] funct3;
        logic [11:7]  rd;
        logic [6:0]   opcode;
    } instruction_itype_t;

    typedef struct packed {
        logic [31:25] immhi;
        logic [24:20] rs2;
        logic [19:15] rs1;
        logic [14:12] funct3;
        logic [11:7]  immlo;
        logic [6:0]   opcode;
    } instruction_stype_t;

    typedef struct packed {
        logic [31:31] imm12;
        logic [30:25] imm10_5;
        logic [24:20] rs2;
        logic [19:15] rs1;
        logic [14:12] funct3;
        logic [11:8]  imm4_1;
        logic [7:7]   imm11;
        logic [6:0]   opcode;
    } instruction_btype_t;

    typedef struct packed {
        logic [31:12] imm;
        logic [11:7]  rd;
        logic [6:0]   opcode;
    } instruction_utype_t;

    typedef struct packed {
        logic [31:31] imm20;
        logic [30:21] imm10_1;
        logic [20:20] imm11;
        logic [19:12] imm19_12;
        logic [11:7]  rd;
        logic [6:0]   opcode;
    } instruction_jtype_t;

    typedef union packed {
        logic [31:0]          raw;
        instruction_generic_t generic;
        instruction_rtype_t   rtype;
        instruction_itype_t   itype;
        instruction_stype_t   stype;
        instruction_btype_t   btype;
        instruction_utype_t   utype;
        instruction_jtype_t   jtype;
    } instruction_t;

`ifndef LESS_EXPRESSIVE_GRAMMAR
    // RISC-V command generator
    function automatic instruction_t make_add(input logic [4:0] rd, input logic [4:0] rs1,
                                              input logic [4:0] rs2);
        instruction_t inst;
        inst.rtype.funct7 = FN7_ADD_SRL;
        inst.rtype.rs2    = rs2;
        inst.rtype.rs1    = rs1;
        inst.rtype.funct3 = FN3_ADD_SUB;
        inst.rtype.rd     = rd;
        inst.rtype.opcode = OP_ALU_R;
        return inst;
    endfunction

    function automatic instruction_t make_sub(input logic [4:0] rd, input logic [4:0] rs1,
                                              input logic [4:0] rs2);
        instruction_t inst;
        inst.rtype.funct7 = FN7_SUB_SRA;
        inst.rtype.rs2    = rs2;
        inst.rtype.rs1    = rs1;
        inst.rtype.funct3 = FN3_ADD_SUB;
        inst.rtype.rd     = rd;
        inst.rtype.opcode = OP_ALU_R;
        return inst;
    endfunction

    function automatic instruction_t make_and(input logic [4:0] rd, input logic [4:0] rs1,
                                              input logic [4:0] rs2);
        instruction_t inst;
        inst.rtype.funct7 = FN7_ADD_SRL;
        inst.rtype.rs2    = rs2;
        inst.rtype.rs1    = rs1;
        inst.rtype.funct3 = FN3_AND;
        inst.rtype.rd     = rd;
        inst.rtype.opcode = OP_ALU_R;
        return inst;
    endfunction

    function automatic instruction_t make_or(input logic [4:0] rd, input logic [4:0] rs1,
                                             input logic [4:0] rs2);
        instruction_t inst;
        inst.rtype.funct7 = FN7_ADD_SRL;
        inst.rtype.rs2    = rs2;
        inst.rtype.rs1    = rs1;
        inst.rtype.funct3 = FN3_OR;
        inst.rtype.rd     = rd;
        inst.rtype.opcode = OP_ALU_R;
        return inst;
    endfunction

    function automatic instruction_t make_xor(input logic [4:0] rd, input logic [4:0] rs1,
                                              input logic [4:0] rs2);
        instruction_t inst;
        inst.rtype.funct7 = FN7_ADD_SRL;
        inst.rtype.rs2    = rs2;
        inst.rtype.rs1    = rs1;
        inst.rtype.funct3 = FN3_XOR;
        inst.rtype.rd     = rd;
        inst.rtype.opcode = OP_ALU_R;
        return inst;
    endfunction

    // I-type instructions
    function automatic instruction_t make_addi(input logic [4:0] rd, input logic [4:0] rs1,
                                               input logic [11:0] imm);
        instruction_t inst;
        inst.itype.imm    = imm;
        inst.itype.rs1    = rs1;
        inst.itype.funct3 = FN3_ADD_SUB;
        inst.itype.rd     = rd;
        inst.itype.opcode = OP_ALU_I;
        return inst;
    endfunction

    function automatic instruction_t make_li(input logic [4:0] rd, input logic [11:0] imm);
        return make_addi(rd, ZERO, imm);
    endfunction

    function automatic instruction_t make_nop();
        return make_addi(5'd0, 5'd0, 12'd0);
    endfunction

    function automatic instruction_t make_andi(input logic [4:0] rd, input logic [4:0] rs1,
                                               input logic [11:0] imm);
        instruction_t inst;
        inst.itype.imm    = imm;
        inst.itype.rs1    = rs1;
        inst.itype.funct3 = FN3_AND;
        inst.itype.rd     = rd;
        inst.itype.opcode = OP_ALU_I;
        return inst;
    endfunction

    function automatic instruction_t make_ori(input logic [4:0] rd, input logic [4:0] rs1,
                                              input logic [11:0] imm);
        instruction_t inst;
        inst.itype.imm    = imm;
        inst.itype.rs1    = rs1;
        inst.itype.funct3 = FN3_OR;
        inst.itype.rd     = rd;
        inst.itype.opcode = OP_ALU_I;
        return inst;
    endfunction

    function automatic instruction_t make_xori(input logic [4:0] rd, input logic [4:0] rs1,
                                               input logic [11:0] imm);
        instruction_t inst;
        inst.itype.imm    = imm;
        inst.itype.rs1    = rs1;
        inst.itype.funct3 = FN3_XOR;
        inst.itype.rd     = rd;
        inst.itype.opcode = OP_ALU_I;
        return inst;
    endfunction

    // Load instructions (I-type)
    function automatic instruction_t make_lb(input logic [4:0] rd, input logic [4:0] rs1,
                                             input logic [11:0] imm);
        instruction_t inst;
        inst.itype.imm    = imm;
        inst.itype.rs1    = rs1;
        inst.itype.funct3 = FN3_BYTE;
        inst.itype.rd     = rd;
        inst.itype.opcode = OP_LD;
        return inst;
    endfunction

    function automatic instruction_t make_lbu(input logic [4:0] rd, input logic [4:0] rs1,
                                              input logic [11:0] imm);
        instruction_t inst;
        inst.itype.imm    = imm;
        inst.itype.rs1    = rs1;
        inst.itype.funct3 = FN3_BYTE_U;
        inst.itype.rd     = rd;
        inst.itype.opcode = OP_LD;
        return inst;
    endfunction

    function automatic instruction_t make_lh(input logic [4:0] rd, input logic [4:0] rs1,
                                             input logic [11:0] imm);
        instruction_t inst;
        inst.itype.imm    = imm;
        inst.itype.rs1    = rs1;
        inst.itype.funct3 = FN3_HALF;
        inst.itype.rd     = rd;
        inst.itype.opcode = OP_LD;
        return inst;
    endfunction

    function automatic instruction_t make_lhu(input logic [4:0] rd, input logic [4:0] rs1,
                                              input logic [11:0] imm);
        instruction_t inst;
        inst.itype.imm    = imm;
        inst.itype.rs1    = rs1;
        inst.itype.funct3 = FN3_HALF_U;
        inst.itype.rd     = rd;
        inst.itype.opcode = OP_LD;
        return inst;
    endfunction

    function automatic instruction_t make_lw(input logic [4:0] rd, input logic [4:0] rs1,
                                             input logic [11:0] imm);
        instruction_t inst;
        inst.itype.imm    = imm;
        inst.itype.rs1    = rs1;
        inst.itype.funct3 = FN3_WORD;
        inst.itype.rd     = rd;
        inst.itype.opcode = OP_LD;
        return inst;
    endfunction

    // Store instructions (S-type)
    function automatic instruction_t make_sb(input logic [4:0] rs2, input logic [4:0] rs1,
                                             input logic [11:0] imm);
        instruction_t inst;
        inst.stype.immhi  = imm[11:5];
        inst.stype.rs2    = rs2;
        inst.stype.rs1    = rs1;
        inst.stype.funct3 = FN3_BYTE;
        inst.stype.immlo  = imm[4:0];
        inst.stype.opcode = OP_ST;
        return inst;
    endfunction

    function automatic instruction_t make_sh(input logic [4:0] rs2, input logic [4:0] rs1,
                                             input logic [11:0] imm);
        instruction_t inst;
        inst.stype.immhi    = imm[11:5];
        inst.stype.rs2    = rs2;
        inst.stype.rs1    = rs1;
        inst.stype.funct3 = FN3_HALF;
        inst.stype.immlo  = imm[4:0];
        inst.stype.opcode = OP_ST;
        return inst;
    endfunction

    function automatic instruction_t make_sw(input logic [4:0] rs2, input logic [4:0] rs1,
                                             input logic [11:0] imm);
        instruction_t inst;
        inst.stype.immhi    = imm[11:5];
        inst.stype.rs2    = rs2;
        inst.stype.rs1    = rs1;
        inst.stype.funct3 = FN3_WORD;
        inst.stype.immlo  = imm[4:0];
        inst.stype.opcode = OP_ST;
        return inst;
    endfunction

    function automatic instruction_t make_mv(input logic [4:0] rd, input logic [4:0] rs1);
        return make_addi(rd, rs1, 12'd0);
    endfunction

    // Branch instructions (B-type)
    function automatic instruction_t make_beq(input logic [4:0] rs1, input logic [4:0] rs2,
                                              input logic [12:0] imm);
        instruction_t inst;
        inst.btype.imm12   = imm[12:12];
        inst.btype.imm10_5 = imm[10:5];
        inst.btype.rs2     = rs2;
        inst.btype.rs1     = rs1;
        inst.btype.funct3  = FN3_BEQ;
        inst.btype.imm4_1  = imm[4:1];
        inst.btype.imm11   = imm[11:11];
        inst.btype.opcode  = OP_BR;
        return inst;
    endfunction

    function automatic instruction_t make_bne(input logic [4:0] rs1, input logic [4:0] rs2,
                                              input logic [12:0] imm);
        instruction_t inst;
        inst.btype.imm12   = imm[12:12];
        inst.btype.imm10_5 = imm[10:5];
        inst.btype.rs2    = rs2;
        inst.btype.rs1    = rs1;
        inst.btype.funct3 = FN3_BNE;
        inst.btype.imm4_1  = imm[4:1];
        inst.btype.imm11   = imm[11:11];
        inst.btype.opcode = OP_BR;
        return inst;
    endfunction

    function automatic instruction_t make_blt(input logic [4:0] rs1, input logic [4:0] rs2,
                                              input logic [12:0] imm);
        instruction_t inst;
        inst.btype.imm12   = imm[12:12];
        inst.btype.imm10_5 = imm[10:5];
        inst.btype.rs2    = rs2;
        inst.btype.rs1    = rs1;
        inst.btype.funct3 = FN3_BLT;
        inst.btype.imm4_1  = imm[4:1];
        inst.btype.imm11   = imm[11:11];
        inst.btype.opcode = OP_BR;
        return inst;
    endfunction

    function automatic instruction_t make_bge(input logic [4:0] rs1, input logic [4:0] rs2,
                                              input logic [12:0] imm);
        instruction_t inst;
        inst.btype.imm12   = imm[12:12];
        inst.btype.imm10_5 = imm[10:5];
        inst.btype.rs2    = rs2;
        inst.btype.rs1    = rs1;
        inst.btype.funct3 = FN3_BGE;
        inst.btype.imm4_1  = imm[4:1];
        inst.btype.imm11   = imm[11:11];
        inst.btype.opcode = OP_BR;
        return inst;
    endfunction

    function automatic instruction_t make_bltu(input logic [4:0] rs1, input logic [4:0] rs2,
                                               input logic [12:0] imm);
        instruction_t inst;
        inst.btype.imm12   = imm[12:12];
        inst.btype.imm10_5 = imm[10:5];
        inst.btype.rs2    = rs2;
        inst.btype.rs1    = rs1;
        inst.btype.funct3 = FN3_BLTU;
        inst.btype.imm4_1  = imm[4:1];
        inst.btype.imm11   = imm[11:11];
        inst.btype.opcode = OP_BR;
        return inst;
    endfunction

    function automatic instruction_t make_bgeu(input logic [4:0] rs1, input logic [4:0] rs2,
                                               input logic [12:0] imm);
        instruction_t inst;
        inst.btype.imm12   = imm[12:12];
        inst.btype.imm10_5 = imm[10:5];
        inst.btype.rs2    = rs2;
        inst.btype.rs1    = rs1;
        inst.btype.funct3 = FN3_BGEU;
        inst.btype.imm4_1  = imm[4:1];
        inst.btype.imm11   = imm[11:11];
        inst.btype.opcode = OP_BR;
        return inst;
    endfunction

    function automatic instruction_t make_bgt(input logic [4:0] rs1, input logic [4:0] rs2,
                                              input logic [12:0] imm);
        return make_blt(rs2, rs1, imm);
    endfunction

    function automatic instruction_t make_beqz(input logic [4:0] rs1, input logic [12:0] imm);
        return make_beq(rs1, 5'd0, imm);
    endfunction

    function automatic instruction_t make_jal(input logic [4:0] rd, input logic [20:0] imm);
        instruction_t inst;
        inst.jtype.imm20    = imm[20:20];
        inst.jtype.imm10_1  = imm[10:1];
        inst.jtype.imm11    = imm[11:11];
        inst.jtype.imm19_12 = imm[19:12];
        inst.jtype.rd       = rd;
        inst.jtype.opcode   = 7'b1101111;
        return inst;
    endfunction

    function automatic instruction_t make_j(input logic [31:0] addr, input logic [31:0] currPc);
        logic [31:0] offset = $signed(addr) - $signed(currPc);
        // $display("%h = %h - %h\n", offset, currPc, addr);
        return make_jal(ZERO, offset[20:0]);
    endfunction

    // U-type instructions (LUI, AUIPC)
    function automatic instruction_t make_lui(input logic [4:0] rd, input logic [31:12] imm);
        instruction_t inst;
        inst.utype.imm    = imm;
        inst.utype.rd     = rd;
        inst.utype.opcode = OP_LUI;
        return inst;
    endfunction

    // function automatic instruction_t make_auipc(input logic [4:0] rd, input logic [31:12] imm);
    //     instruction_t inst;
    //     inst.utype.imm    = imm;
    //     inst.utype.rd     = rd;
    //     inst.utype.opcode = OP_AUIPC;
    //     return inst;
    // endfunction

    // J-type instruction (JAL)

    // I-type JALR
    // function automatic instruction_t make_jalr(input logic [4:0] rd, input logic [4:0] rs1,
    //                                            input logic [11:0] imm);
    //     instruction_t inst;
    //     inst.itype.imm    = imm;
    //     inst.itype.rs1    = rs1;
    //     inst.itype.funct3 = 3'b000;
    //     inst.itype.rd     = rd;
    //     inst.itype.opcode = OP_JALR;
    //     return inst;
    // endfunction
`endif // LESS_EXPRESSIVE_GRAMMAR
    // Register indices
    parameter ZERO = 5'd0;
    parameter RA = 5'd1;
    parameter SP = 5'd2;
    parameter GP = 5'd3;
    parameter TP = 5'd4;
    parameter T0 = 5'd5;
    parameter T1 = 5'd6;
    parameter T2 = 5'd7;
    parameter S0 = 5'd8;
    parameter S1 = 5'd9;
    parameter A0 = 5'd10;
    parameter A1 = 5'd11;
    parameter A2 = 5'd12;
    parameter A3 = 5'd13;
    parameter A4 = 5'd14;
    parameter A5 = 5'd15;
    parameter A6 = 5'd16;
    parameter A7 = 5'd17;
    parameter S2 = 5'd18;
    parameter S3 = 5'd19;
    parameter S4 = 5'd20;
    parameter S5 = 5'd21;
    parameter S6 = 5'd22;
    parameter S7 = 5'd23;
    parameter S8 = 5'd24;
    parameter S9 = 5'd25;
    parameter S10 = 5'd26;
    parameter S11 = 5'd27;
    parameter T3 = 5'd28;
    parameter T4 = 5'd29;
    parameter T5 = 5'd30;
    parameter T6 = 5'd31;

`ifndef LESS_EXPRESSIVE_GRAMMAR
endpackage : pkg_riscv_instructions
`endif

`endif // PKG_RISCV_INSTRUCTIONS_SV
