.section .text
.globl _start
_start:
    # parameter TEST_MEMORY = 0x00000005
    li  s0, 0x5          # S0 = TEST_MEMORY

    # store value
    li  t1, 123
    sw  t1, 0(s0)

    # create dependency
    li  t1, 1
    lw  t2, 0(s0)
    add t1, t1, t2

    # end of program (no syscall in simulation)
    nop
