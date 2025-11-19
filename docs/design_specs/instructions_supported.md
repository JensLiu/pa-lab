# Instructions supported

This document presents the instructions that are supported by the implemented CPU. The instructions are a subset of RISC-V's ISA, all the codifications are also the same. 

## Types of instructions based on the operation

### Arithmetic
- ADD (add rd, rs1, rs2), rd = rs1 + rs2
- ADDI (addi rd, rs1, imm), rd = rs1 + imm
- SUB (sub rd, rs1, rs2), rd = rs1 - rs2
- MUL (mul rd, rs1, rs2), rd = (rs1 * rs2)[31:0]
### Bitwise logic
- AND (and rd, rs1, rs2), rd = rs1 & rs2
- ANDI (andi rd, rs1, imm), rd = rs1 & imm
- OR (or rd, rs1, rs2), rd = rs1 | rs2
- ORI (ori rd, rs1, imm), rd = rs1 | imm
- XOR (xor rd, rs1, rs2), rd = rs1 ^ rs2
- XORI (xori rd, rs1, imm), rd = rs1 ^ imm
### Shift

### Load inmediate
- LI (li rd, imm), rd = imm
- LUI (lui rd, imm), rd = imm << 12
### Load and store
- LB (lb rd, imm(rs1)), rd = mem[rs1+imm][0:7]
- LBU (lbu rd, imm(rs1)), rd = mem[rs1+imm][0:7]
- LH (lh rd, imm(rs1)), rd = mem[rs1+imm][0:15]
- LHU (lhu rd, imm(rs1)), rd = mem[rs1+imm][0:15]
- LW (lw rd, imm(rs1)), rd = mem[rs1+imm]
- SB (sb rs2, imm(rs1)), mem[rs1+imm][0:7] = rs2
- SH (sh rs2, imm(rs1)), mem[rs1+imm][0:15] = rs2
- SW (sw rs2, imm(rs1)), mem[rs1+imm][0:7] = rs2
### Branch
- BEQ (beq rs1, rs2, imm), if(rs1 == rs2) pc += imm
- BNE (beqz rs1, imm), if(rs1 != rs2) pc += imm
- BLT (blt rs1, rs2, imm), if(rs1 < rs2) pc += imm
- BGE (bge rs1, rs2, imm), if(rs1 ≥ rs2) pc += imm
- BLTU (bltu rs1, rs2, imm), if(rs1 < rs2) pc += imm
- BGEU (bgeu rs1, rs2, imm), if(rs1 ≥ rs2) pc += imm
- BGT (bgt rs1, rs2, imm), if(rs1 > rs2) pc += imm
- BEQZ (beqz rs1, imm), if(rs1 == 0) pc += imm

### JUMP
- J (j imm), pc += imm
- JAL (jal rd, imm), rd = pc+4; pc += imm
- CALL (call symbol), ra = pc+4; pc = &symbol

### SPECIAL
- MV (mov rd, rs1) rd = rs1
- NOP (does nothing)
- IRET (return from supervisor)