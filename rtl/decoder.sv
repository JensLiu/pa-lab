`timescale 1ns / 1ps
`include "../includes/includes.sv"

module decoder
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;
(
    input  instruction_t inst,
    output inst_info_t   info
);

    inst_opcode_t opcode = inst_opcode_t'(inst.generic.opcode);
    logic [2:0] funct3 = inst.generic.funct3;

    always_comb begin
        info.rs1 = inst.generic.rs1;
        info.rs2 = inst.generic.rs2;
        info.rd = inst.generic.rd;
        info.imm = IMM_32_WHATEVER;
        info.cmpIsSigned = TRUE;
        info.isStore = FALSE;
        info.isLoad = FALSE;
        info.aluUseImm = FALSE;
        info.isWriteback = FALSE;
        info.aluOp = ALU_INVALID;
        info.branchType = BR_INVALID;
        info.stldDataLen = DL_INVALID;


        // ALU begin
        if (opcode == OP_ALU_R || opcode == OP_ALU_I) begin
            info.isWriteback = TRUE;
            case (funct3)
                FN3_ADD_SUB: begin
                    if (opcode == OP_ALU_I) begin
                        info.aluOp = ALU_ADD;  // <- addi uses I-type
                    end else begin
                        case (inst.rtype.funct7)  // <- add & sub use R-type
                            FN7_ADD_SRL: info.aluOp = ALU_ADD;
                            FN7_SUB_SRA: info.aluOp = ALU_SUB;
                            default: info.aluOp = ALU_INVALID;
                        endcase
                    end
                end
                FN3_SLL:  info.aluOp = ALU_SLL;
                FN3_SLTU: info.aluOp = ALU_SLTU;
                FN3_XOR:  info.aluOp = ALU_XOR;
                FN3_SRL_SRA: begin  // <- srli & srai use I-Type
                    if (opcode == OP_ALU_I) begin

                        if (inst.itype.imm[11:5] == 7'b0100000) begin
                            info.aluOp = ALU_SRA;
                        end else begin
                            info.aluOp = ALU_SRL;
                        end
                    end else begin
                        case (inst.rtype.funct7)
                            FN7_ADD_SRL: info.aluOp = ALU_SRL;
                            FN7_SUB_SRA: info.aluOp = ALU_SRA;
                            default: info.aluOp = ALU_INVALID;
                        endcase
                    end
                end
                FN3_OR:   info.aluOp = ALU_OR;
                FN3_AND:  info.aluOp = ALU_AND;
                default:  info.aluOp = ALU_INVALID;
            endcase
        end

        if (opcode == OP_ALU_I) begin
            if (funct3 == FN3_SRL_SRA) begin
                // shift instructions use shamt in imm[4:0]
                info.imm = {27'b0, inst.itype.imm[24:20]};
            end else if (funct3 == FN3_ADD_SUB) begin
                info.imm = {{20{inst.itype.imm[31]}}, inst.itype.imm};
            end
            info.aluUseImm = TRUE;
            info.rs2 = REG_NR_INVALID_FALLBACK;
        end
        // ALU end

        // LOAD AND STORE begin
        if (opcode == OP_LD || opcode == OP_ST) begin
            info.aluUseImm = TRUE;
            info.aluOp = ALU_ADD;  // <- address calculation
            case (funct3)
                FN3_BYTE, FN3_HALF:     info.stldSignedness = SS_SIGNED;
                FN3_BYTE_U, FN3_HALF_U: info.stldSignedness = SS_UNSIGNED;
                default:                info.stldSignedness = SS_INVALID;
            endcase
            case (funct3)
                FN3_BYTE, FN3_BYTE_U: begin
                    info.stldDataLen = DL_BYTE;
                end
                FN3_HALF, FN3_HALF_U: begin
                    info.stldDataLen = DL_HALF;
                end
                FN3_WORD: begin
                    info.stldDataLen = DL_WORD;
                end
                default: info.stldDataLen = DL_INVALID;
            endcase
        end

        if (opcode == OP_LD) begin
            info.isLoad = TRUE;
            info.aluUseImm = TRUE;
            info.isWriteback = TRUE;
            info.rs2 = REG_NR_INVALID_FALLBACK;
            info.imm = {{20{inst.itype.imm[31]}}, inst.itype.imm};
        end else if (opcode == OP_ST) begin
            info.isStore = TRUE;
            info.aluUseImm = TRUE;
            info.rd = REG_NR_INVALID_FALLBACK;
            info.imm = {{20{inst.stype.immhi[31]}}, inst.stype.immhi, inst.stype.immlo};
        end
        // LOAD AND STORE end

        // BRANCH begin
        if (opcode == OP_BR) begin
            // Note: In RISC-V, the zero-th bit in B-Type is always zero
            //       since instructions must be aligned by 2
            info.imm = {  // offset
                {19{inst.btype.imm12}},
                inst.btype.imm12,
                inst.btype.imm11,
                inst.btype.imm10_5,
                inst.btype.imm4_1,
                1'b0
            };
            info.rd = REG_NR_INVALID_FALLBACK;
            case (funct3)
                FN3_BEQ:  info.branchType = BR_BEQ;
                FN3_BNE:  info.branchType = BR_BNE;
                FN3_BLT:  info.branchType = BR_BLT;
                FN3_BGE:  info.branchType = BR_BGE;
                FN3_BLTU: info.branchType = BR_BLTU;
                FN3_BGEU: info.branchType = BR_BGEU;
                default:  info.branchType = BR_INVALID;
            endcase
            case (funct3)
                FN3_BLTU, FN3_BGEU: info.cmpIsSigned = FALSE;
                default: info.cmpIsSigned = TRUE;
            endcase
        end else if (opcode == OP_JAL) begin
            info.imm = {
                {11{1'b0}},
                inst.jtype.imm20,
                inst.jtype.imm19_12,
                inst.jtype.imm11,
                inst.jtype.imm10_1,
                1'b0
            };
            info.branchType = BR_UNCOND;
            info.rs1 = REG_NR_INVALID_FALLBACK;
            info.rs2 = REG_NR_INVALID_FALLBACK;
        end

        // BRANCH end

        // LUI begin
        if (opcode == OP_LUI) begin
            info.imm   = {inst.utype.imm, {12{1'b0}}};
            info.aluOp = ALU_ADD;
            info.rs1   = REG_NR_INVALID_FALLBACK;
            info.rs2   = REG_NR_INVALID_FALLBACK;
        end
        // LUI end

    end

endmodule
