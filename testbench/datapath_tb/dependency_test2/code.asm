.section .text
.globl _start
_start:
    # dependency_test2: repeatedly double starting at 1
    li  t1, 1
    add t1, t1, t1  # 2
    add t1, t1, t1  # 4
    add t1, t1, t1  # 8
    add t1, t1, t1  # 16
    add t1, t1, t1  # 32
    add t1, t1, t1  # 64
    add t1, t1, t1  # 128
    add t1, t1, t1  # 256
    add t1, t1, t1  # 512
    add t1, t1, t1  # 1024
    # end of program (no syscall in simulation)
    nop
