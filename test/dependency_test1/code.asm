.section .text
.globl _start
_start:
    # dependency_test1
    li  t2, 0x123
    li  t3, 0x234
    add t1, t2, t3
    add t1, t1, t1

    # end of program (no syscall in simulation)
    nop
