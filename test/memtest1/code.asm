.section .text
.globl _start
_start:
    # parameter TEST_MEMORY = 0x00000005
    li  s0, 0x5          # S0 = TEST_MEMORY

    # build 0xFFFF1234 in t1
    lui t1, 0xFFFF1
    ori t1, t1, 0x234

    sw  t1, 0(s0)
    sh  t1, 4(s0)
    sb  t1, 6(s0)

    lw  t2, 0(s0)
    lh  t3, 4(s0)
    lb  t4, 6(s0)

    # end of program (no syscall in simulation)
    nop
