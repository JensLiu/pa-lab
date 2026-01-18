    .global _start
_start:
    li      t0, 1   # x <- 1
    li      s0, 0   # i <- 0
    li      s1, 10  # N_ITERS

loop:
    bge     s0, s1, loop_exit
    add     t0, t0, t0  # x <- x + 1
    addi    s0, s0, 1   # i <- i + 1  
    j       loop

loop_exit:
    addi    t0, t0, 1   # x <- x + 1
    # STOP *(unsigned int *)(0xcafebabe) = 0xbeafbabe