.section .text
.globl _start
_start:
    # dependency_test2: repeatedly double starting at 1
    li  t1, 1
    add t1, t1, t1
    add t1, t1, t1
    add t1, t1, t1
    add t1, t1, t1
    add t1, t1, t1
    add t1, t1, t1
    add t1, t1, t1
    add t1, t1, t1
    add t1, t1, t1
    add t1, t1, t1

    # end of program (no syscall in simulation)
    nop
