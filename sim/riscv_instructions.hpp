#ifndef RISCV_INSTRUCTIONS_HPP
#define RISCV_INSTRUCTIONS_HPP

#include <cstdint>
#include <stdexcept>
#include <string>

namespace RISCVInstructions {

// Opcodes
enum class Opcode : uint8_t {
  OP_ALU_R = 0b0110011, // ALU: register-register
  OP_ALU_I = 0b0010011, // ALU: register-immediate
  OP_LD = 0b0000011,    // Load
  OP_ST = 0b0100011,    // Store
  OP_BR = 0b1100011,    // Branch
  OP_LUI = 0b0110111,   // Load Upper Immediate
  OP_AUIPC = 0b0010111, // Add Upper Immediate to PC
  OP_JAL = 0b1101111,   // Jump and Link
  OP_JALR = 0b1100111   // Jump and Link Register
};

// Funct3 for ALU operations
enum class Funct3ALU : uint8_t {
  ADD_SUB = 0b000,
  SLL = 0b001,
  SLT = 0b010,
  SLTU = 0b011,
  XOR = 0b100,
  SRL_SRA = 0b101,
  OR = 0b110,
  AND = 0b111
};

// Funct3 for Load/Store operations
enum class Funct3LDST : uint8_t {
  BYTE = 0b000,   // LB/SB
  HALF = 0b001,   // LH/SH
  WORD = 0b010,   // LW/SW
  BYTE_U = 0b100, // LBU
  HALF_U = 0b101  // LHU
};

// Funct3 for Branch operations
enum class Funct3BR : uint8_t {
  BEQ = 0b000,
  BNE = 0b001,
  BLT = 0b100,
  BGE = 0b101,
  BLTU = 0b110,
  BGEU = 0b111
};

// Funct7 for ALU operations
enum class Funct7ALU : uint8_t {
  ADD_SRL = 0b0000000,
  SUB_SRA = 0b0100000,
  MUL = 0b0000001 // For M extension
};

// Instruction class that handles bit manipulation directly
class Instruction {
public:
  uint32_t raw;

  Instruction() : raw(0) {}
  explicit Instruction(uint32_t value) : raw(value) {}

  // Common field getters
  uint8_t getOpcode() const { return raw & 0x7F; }
  uint8_t getRd() const { return (raw >> 7) & 0x1F; }
  uint8_t getFunct3() const { return (raw >> 12) & 0x07; }
  uint8_t getRs1() const { return (raw >> 15) & 0x1F; }
  uint8_t getRs2() const { return (raw >> 20) & 0x1F; }
  uint8_t getFunct7() const { return (raw >> 25) & 0x7F; }

  // I-Type immediate
  int32_t getImmI() const {
    uint32_t imm = (raw >> 20) & 0xFFF;
    return signExtend(imm, 12);
  }

  // S-Type immediate
  int32_t getImmS() const {
    uint32_t imm = ((raw >> 25) << 5) | ((raw >> 7) & 0x1F);
    return signExtend(imm, 12);
  }

  // B-Type immediate
  int32_t getImmB() const {
    uint32_t imm = ((raw >> 31) << 12) | (((raw >> 7) & 0x1) << 11) |
                   (((raw >> 25) & 0x3F) << 5) | (((raw >> 8) & 0xF) << 1);
    return signExtend(imm, 13);
  }

  // U-Type immediate
  int32_t getImmU() const { return raw & 0xFFFFF000; }

  // J-Type immediate
  int32_t getImmJ() const {
    uint32_t imm = ((raw >> 31) << 20) | (((raw >> 12) & 0xFF) << 12) |
                   (((raw >> 20) & 0x1) << 11) | (((raw >> 21) & 0x3FF) << 1);
    return signExtend(imm, 21);
  }

private:
  static int32_t signExtend(uint32_t value, int bits) {
    int32_t sign_bit = 1 << (bits - 1);
    if (value & sign_bit) {
      return value | (~0U << bits);
    }
    return value;
  }
};

// Decoded instruction information
struct DecodedInstruction {
  Opcode opcode;
  uint8_t rd;
  uint8_t rs1;
  uint8_t rs2;
  uint8_t funct3;
  uint8_t funct7;
  int32_t imm;
  std::string mnemonic;
  std::string format; // "R", "I", "S", "B", "U", "J"
};

class RISCVDecoder {
public:
  // Decode a 32-bit instruction
  static DecodedInstruction decode(uint32_t instruction) {
    Instruction inst(instruction);
    DecodedInstruction decoded;

    decoded.opcode = static_cast<Opcode>(inst.getOpcode());
    decoded.rd = inst.getRd();
    decoded.rs1 = inst.getRs1();
    decoded.rs2 = inst.getRs2();
    decoded.funct3 = inst.getFunct3();
    decoded.funct7 = inst.getFunct7();

    // Decode based on opcode
    switch (decoded.opcode) {
    case Opcode::OP_ALU_R:
      decoded.format = "R";
      decoded.imm = 0;
      decoded.mnemonic = decodeRType(decoded);
      break;

    case Opcode::OP_ALU_I:
    case Opcode::OP_LD:
    case Opcode::OP_JALR:
      decoded.format = "I";
      decoded.imm = inst.getImmI();
      decoded.mnemonic = decodeIType(decoded);
      break;

    case Opcode::OP_ST:
      decoded.format = "S";
      decoded.imm = inst.getImmS();
      decoded.mnemonic = decodeSType(decoded);
      break;

    case Opcode::OP_BR:
      decoded.format = "B";
      decoded.imm = inst.getImmB();
      decoded.mnemonic = decodeBType(decoded);
      break;

    case Opcode::OP_LUI:
    case Opcode::OP_AUIPC:
      decoded.format = "U";
      decoded.imm = inst.getImmU();
      decoded.mnemonic = decodeUType(decoded);
      break;

    case Opcode::OP_JAL:
      decoded.format = "J";
      decoded.imm = inst.getImmJ();
      decoded.mnemonic = decodeJType(decoded);
      break;

    default:
      decoded.format = "UNKNOWN";
      decoded.mnemonic = "UNKNOWN";
      decoded.imm = 0;
    }

    return decoded;
  }

  // Get assembly string representation
  static std::string toAssembly(const DecodedInstruction &decoded) {
    std::string asm_str = decoded.mnemonic;

    if (decoded.format == "R") {
      asm_str += " x" + std::to_string(decoded.rd) + ", x" +
                 std::to_string(decoded.rs1) + ", x" +
                 std::to_string(decoded.rs2);
    } else if (decoded.format == "I") {
      if (decoded.opcode == Opcode::OP_LD ||
          decoded.opcode == Opcode::OP_JALR) {
        asm_str += " x" + std::to_string(decoded.rd) + ", " +
                   std::to_string(decoded.imm) + "(x" +
                   std::to_string(decoded.rs1) + ")";
      } else {
        asm_str += " x" + std::to_string(decoded.rd) + ", x" +
                   std::to_string(decoded.rs1) + ", " +
                   std::to_string(decoded.imm);
      }
    } else if (decoded.format == "S") {
      asm_str += " x" + std::to_string(decoded.rs2) + ", " +
                 std::to_string(decoded.imm) + "(x" +
                 std::to_string(decoded.rs1) + ")";
    } else if (decoded.format == "B") {
      asm_str += " x" + std::to_string(decoded.rs1) + ", x" +
                 std::to_string(decoded.rs2) + ", " +
                 std::to_string(decoded.imm);
    } else if (decoded.format == "U") {
      asm_str += " x" + std::to_string(decoded.rd) + ", " +
                 std::to_string(decoded.imm >> 12);
    } else if (decoded.format == "J") {
      asm_str += " x" + std::to_string(decoded.rd) + ", " +
                 std::to_string(decoded.imm);
    }

    if (asm_str == "addi x0, x0, 0") {
      asm_str = "nop";
    }

    return asm_str;
  }

private:
  // Sign extend a value
  static int32_t signExtend(uint32_t value, int bits) {
    int32_t sign_bit = 1 << (bits - 1);
    if (value & sign_bit) {
      return value | (~0U << bits);
    }
    return value;
  }

  static std::string decodeRType(const DecodedInstruction &decoded) {
    switch (static_cast<Funct3ALU>(decoded.funct3)) {
    case Funct3ALU::ADD_SUB:
      return (decoded.funct7 == 0x00) ? "add" : "sub";
    case Funct3ALU::SLL:
      return "sll";
    case Funct3ALU::SLT:
      return "slt";
    case Funct3ALU::SLTU:
      return "sltu";
    case Funct3ALU::XOR:
      return "xor";
    case Funct3ALU::SRL_SRA:
      return (decoded.funct7 == 0x00) ? "srl" : "sra";
    case Funct3ALU::OR:
      return "or";
    case Funct3ALU::AND:
      return "and";
    default:
      return "UNKNOWN_R";
    }
  }

  static std::string decodeIType(const DecodedInstruction &decoded) {
    if (decoded.opcode == Opcode::OP_LD) {
      switch (static_cast<Funct3LDST>(decoded.funct3)) {
      case Funct3LDST::BYTE:
        return "lb";
      case Funct3LDST::HALF:
        return "lh";
      case Funct3LDST::WORD:
        return "lw";
      case Funct3LDST::BYTE_U:
        return "lbu";
      case Funct3LDST::HALF_U:
        return "lhu";
      default:
        return "UNKNOWN_LOAD";
      }
    } else if (decoded.opcode == Opcode::OP_JALR) {
      return "jalr";
    } else {
      switch (static_cast<Funct3ALU>(decoded.funct3)) {
      case Funct3ALU::ADD_SUB:
        return "addi";
      case Funct3ALU::SLL:
        return "slli";
      case Funct3ALU::SLT:
        return "slti";
      case Funct3ALU::SLTU:
        return "sltiu";
      case Funct3ALU::XOR:
        return "xori";
      case Funct3ALU::SRL_SRA:
        return (decoded.funct7 == 0x00) ? "srli" : "srai";
      case Funct3ALU::OR:
        return "ori";
      case Funct3ALU::AND:
        return "andi";
      default:
        return "UNKNOWN_I";
      }
    }
  }

  static std::string decodeSType(const DecodedInstruction &decoded) {
    switch (static_cast<Funct3LDST>(decoded.funct3)) {
    case Funct3LDST::BYTE:
      return "sb";
    case Funct3LDST::HALF:
      return "sh";
    case Funct3LDST::WORD:
      return "sw";
    default:
      return "UNKNOWN_STORE";
    }
  }

  static std::string decodeBType(const DecodedInstruction &decoded) {
    switch (static_cast<Funct3BR>(decoded.funct3)) {
    case Funct3BR::BEQ:
      return "beq";
    case Funct3BR::BNE:
      return "bne";
    case Funct3BR::BLT:
      return "blt";
    case Funct3BR::BGE:
      return "bge";
    case Funct3BR::BLTU:
      return "bltu";
    case Funct3BR::BGEU:
      return "bgeu";
    default:
      return "UNKNOWN_BRANCH";
    }
  }

  static std::string decodeUType(const DecodedInstruction &decoded) {
    if (decoded.opcode == Opcode::OP_LUI) {
      return "lui";
    } else if (decoded.opcode == Opcode::OP_AUIPC) {
      return "auipc";
    }
    return "UNKNOWN_U";
  }

  static std::string decodeJType(const DecodedInstruction &) { return "jal"; }
};

class RISCVEncoder {
public:
  // R-Type instructions
  static uint32_t encodeRType(uint8_t funct7, uint8_t rs2, uint8_t rs1,
                              uint8_t funct3, uint8_t rd, uint8_t opcode) {
    return (opcode & 0x7F) | ((rd & 0x1F) << 7) | ((funct3 & 0x07) << 12) |
           ((rs1 & 0x1F) << 15) | ((rs2 & 0x1F) << 20) |
           ((funct7 & 0x7F) << 25);
  }

  // I-Type instructions
  static uint32_t encodeIType(uint16_t imm, uint8_t rs1, uint8_t funct3,
                              uint8_t rd, uint8_t opcode) {
    return (opcode & 0x7F) | ((rd & 0x1F) << 7) | ((funct3 & 0x07) << 12) |
           ((rs1 & 0x1F) << 15) | ((imm & 0xFFF) << 20);
  }

  // S-Type instructions
  static uint32_t encodeSType(uint16_t imm, uint8_t rs2, uint8_t rs1,
                              uint8_t funct3, uint8_t opcode) {
    return (opcode & 0x7F) | ((imm & 0x1F) << 7) | ((funct3 & 0x07) << 12) |
           ((rs1 & 0x1F) << 15) | ((rs2 & 0x1F) << 20) |
           (((imm >> 5) & 0x7F) << 25);
  }

  // B-Type instructions
  static uint32_t encodeBType(uint16_t imm, uint8_t rs2, uint8_t rs1,
                              uint8_t funct3, uint8_t opcode) {
    return (opcode & 0x7F) | (((imm >> 11) & 0x1) << 7) |
           (((imm >> 1) & 0xF) << 8) | ((funct3 & 0x07) << 12) |
           ((rs1 & 0x1F) << 15) | ((rs2 & 0x1F) << 20) |
           (((imm >> 5) & 0x3F) << 25) | (((imm >> 12) & 0x1) << 31);
  }

  // U-Type instructions
  static uint32_t encodeUType(uint32_t imm, uint8_t rd, uint8_t opcode) {
    return (opcode & 0x7F) | ((rd & 0x1F) << 7) | (imm & 0xFFFFF000);
  }

  // J-Type instructions
  static uint32_t encodeJType(uint32_t imm, uint8_t rd, uint8_t opcode) {
    return (opcode & 0x7F) | ((rd & 0x1F) << 7) | (((imm >> 12) & 0xFF) << 12) |
           (((imm >> 11) & 0x1) << 20) | (((imm >> 1) & 0x3FF) << 21) |
           (((imm >> 20) & 0x1) << 31);
  }

  // Convenience functions for specific instructions
  static uint32_t ADD(uint8_t rd, uint8_t rs1, uint8_t rs2) {
    return encodeRType(0x00, rs2, rs1, 0x0, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_R));
  }

  static uint32_t SUB(uint8_t rd, uint8_t rs1, uint8_t rs2) {
    return encodeRType(0x20, rs2, rs1, 0x0, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_R));
  }

  static uint32_t AND(uint8_t rd, uint8_t rs1, uint8_t rs2) {
    return encodeRType(0x00, rs2, rs1, 0x7, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_R));
  }

  static uint32_t OR(uint8_t rd, uint8_t rs1, uint8_t rs2) {
    return encodeRType(0x00, rs2, rs1, 0x6, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_R));
  }

  static uint32_t XOR(uint8_t rd, uint8_t rs1, uint8_t rs2) {
    return encodeRType(0x00, rs2, rs1, 0x4, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_R));
  }

  static uint32_t SLL(uint8_t rd, uint8_t rs1, uint8_t rs2) {
    return encodeRType(0x00, rs2, rs1, 0x1, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_R));
  }

  static uint32_t SRL(uint8_t rd, uint8_t rs1, uint8_t rs2) {
    return encodeRType(0x00, rs2, rs1, 0x5, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_R));
  }

  static uint32_t SRA(uint8_t rd, uint8_t rs1, uint8_t rs2) {
    return encodeRType(0x20, rs2, rs1, 0x5, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_R));
  }

  static uint32_t SLT(uint8_t rd, uint8_t rs1, uint8_t rs2) {
    return encodeRType(0x00, rs2, rs1, 0x2, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_R));
  }

  static uint32_t SLTU(uint8_t rd, uint8_t rs1, uint8_t rs2) {
    return encodeRType(0x00, rs2, rs1, 0x3, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_R));
  }

  static uint32_t ADDI(uint8_t rd, uint8_t rs1, int16_t imm) {
    return encodeIType(imm, rs1, 0x0, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_I));
  }

  static uint32_t ANDI(uint8_t rd, uint8_t rs1, int16_t imm) {
    return encodeIType(imm, rs1, 0x7, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_I));
  }

  static uint32_t ORI(uint8_t rd, uint8_t rs1, int16_t imm) {
    return encodeIType(imm, rs1, 0x6, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_I));
  }

  static uint32_t XORI(uint8_t rd, uint8_t rs1, int16_t imm) {
    return encodeIType(imm, rs1, 0x4, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_I));
  }

  static uint32_t SLLI(uint8_t rd, uint8_t rs1, uint8_t shamt) {
    return encodeIType(shamt & 0x1F, rs1, 0x1, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_I));
  }

  static uint32_t SRLI(uint8_t rd, uint8_t rs1, uint8_t shamt) {
    return encodeIType(shamt & 0x1F, rs1, 0x5, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_I));
  }

  static uint32_t SRAI(uint8_t rd, uint8_t rs1, uint8_t shamt) {
    return encodeIType(0x400 | (shamt & 0x1F), rs1, 0x5, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_I));
  }

  static uint32_t SLTI(uint8_t rd, uint8_t rs1, int16_t imm) {
    return encodeIType(imm, rs1, 0x2, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_I));
  }

  static uint32_t SLTIU(uint8_t rd, uint8_t rs1, int16_t imm) {
    return encodeIType(imm, rs1, 0x3, rd,
                       static_cast<uint8_t>(Opcode::OP_ALU_I));
  }

  static uint32_t LB(uint8_t rd, uint8_t rs1, int16_t imm) {
    return encodeIType(imm, rs1, 0x0, rd, static_cast<uint8_t>(Opcode::OP_LD));
  }

  static uint32_t LH(uint8_t rd, uint8_t rs1, int16_t imm) {
    return encodeIType(imm, rs1, 0x1, rd, static_cast<uint8_t>(Opcode::OP_LD));
  }

  static uint32_t LW(uint8_t rd, uint8_t rs1, int16_t imm) {
    return encodeIType(imm, rs1, 0x2, rd, static_cast<uint8_t>(Opcode::OP_LD));
  }

  static uint32_t LBU(uint8_t rd, uint8_t rs1, int16_t imm) {
    return encodeIType(imm, rs1, 0x4, rd, static_cast<uint8_t>(Opcode::OP_LD));
  }

  static uint32_t LHU(uint8_t rd, uint8_t rs1, int16_t imm) {
    return encodeIType(imm, rs1, 0x5, rd, static_cast<uint8_t>(Opcode::OP_LD));
  }

  static uint32_t SB(uint8_t rs2, uint8_t rs1, int16_t imm) {
    return encodeSType(imm, rs2, rs1, 0x0, static_cast<uint8_t>(Opcode::OP_ST));
  }

  static uint32_t SH(uint8_t rs2, uint8_t rs1, int16_t imm) {
    return encodeSType(imm, rs2, rs1, 0x1, static_cast<uint8_t>(Opcode::OP_ST));
  }

  static uint32_t SW(uint8_t rs2, uint8_t rs1, int16_t imm) {
    return encodeSType(imm, rs2, rs1, 0x2, static_cast<uint8_t>(Opcode::OP_ST));
  }

  static uint32_t BEQ(uint8_t rs1, uint8_t rs2, int16_t imm) {
    return encodeBType(imm, rs2, rs1, 0x0, static_cast<uint8_t>(Opcode::OP_BR));
  }

  static uint32_t BNE(uint8_t rs1, uint8_t rs2, int16_t imm) {
    return encodeBType(imm, rs2, rs1, 0x1, static_cast<uint8_t>(Opcode::OP_BR));
  }

  static uint32_t BLT(uint8_t rs1, uint8_t rs2, int16_t imm) {
    return encodeBType(imm, rs2, rs1, 0x4, static_cast<uint8_t>(Opcode::OP_BR));
  }

  static uint32_t BGE(uint8_t rs1, uint8_t rs2, int16_t imm) {
    return encodeBType(imm, rs2, rs1, 0x5, static_cast<uint8_t>(Opcode::OP_BR));
  }

  static uint32_t BLTU(uint8_t rs1, uint8_t rs2, int16_t imm) {
    return encodeBType(imm, rs2, rs1, 0x6, static_cast<uint8_t>(Opcode::OP_BR));
  }

  static uint32_t BGEU(uint8_t rs1, uint8_t rs2, int16_t imm) {
    return encodeBType(imm, rs2, rs1, 0x7, static_cast<uint8_t>(Opcode::OP_BR));
  }

  static uint32_t LUI(uint8_t rd, uint32_t imm) {
    return encodeUType(imm, rd, static_cast<uint8_t>(Opcode::OP_LUI));
  }

  static uint32_t AUIPC(uint8_t rd, uint32_t imm) {
    return encodeUType(imm, rd, static_cast<uint8_t>(Opcode::OP_AUIPC));
  }

  static uint32_t JAL(uint8_t rd, int32_t imm) {
    return encodeJType(imm, rd, static_cast<uint8_t>(Opcode::OP_JAL));
  }

  static uint32_t JALR(uint8_t rd, uint8_t rs1, int16_t imm) {
    return encodeIType(imm, rs1, 0x0, rd,
                       static_cast<uint8_t>(Opcode::OP_JALR));
  }

  // Pseudo-instructions
  static uint32_t NOP() {
    return ADDI(0, 0, 0); // addi x0, x0, 0
  }

  static uint32_t LI(uint8_t rd, int16_t imm) {
    return ADDI(rd, 0, imm); // addi rd, x0, imm
  }

  static uint32_t MV(uint8_t rd, uint8_t rs1) {
    return ADDI(rd, rs1, 0); // addi rd, rs1, 0
  }
};

} // namespace RISCVInstructions

#endif // RISCV_INSTRUCTIONS_HPP
