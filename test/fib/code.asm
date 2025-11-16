.global _start
_start:
    # compute F(N) where N = 11 (stored in s0)
    li      s0, 11          # s0 = N
    beqz    s0, fib_n_zero
    li      a0, 1
    beq     s0, a0, fib_n_one
    li      a0, 0

    li      s1, 0          # F(i-2) = 0
    li      s2, 1          # F(i-1) = 1
    li      t0, 2          # i = 2

fib_loop:
    bgt     t0, s0, fib_end
    add     s3, s1, s2
    mv      s1, s2
    mv      s2, s3
    addi    t0, t0, 1
    j       fib_loop

fib_n_zero:
    li      a0, 0
    j       exit_program

fib_n_one:
    li      a0, 1
    j       exit_program

fib_end:
    mv      a0, s2

exit_program:
    nop
    # end of program
    nop
