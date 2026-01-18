.text
.global main
main:
    # Initialize registers
    li      x1, 10          # Loop counter N = 10
    li      x2, 0           # Accumulator for addition
    li      x3, 1           # Accumulator for multiplication
    li      x4, 5           # Constant for multiplication
    li      x5, 2           # Constant for addition
    li      x6, 0           # Loop index i = 0

    loop:
    beq     x6, x1, end     # If i == N, exit loop

    # Arithmetic operation (short latency)
    add     x2, x2, x5      # x2 = x2 + 2

    # Multiplication (long latency)
    # This instruction will commit later than the subsequent add if RO is working
    mul     x3, x3, x4      # x3 = x3 * 5

    # Another short latency operation immediately after
    addi    x6, x6, 1       # i++

    j       loop            # Jump back to start

end:
    # Final check results
    # x2 should be 10 * 5 = 50
    # x3 should be 5^10 (large number)

    # Infinite loop to stop execution
    j       end