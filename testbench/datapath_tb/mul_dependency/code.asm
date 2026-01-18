# Testbench: mul_dependency
# Description: Calculates a running sum of products in a loop to test
#              dependencies between MUL, ADD, and Branch instructions.
#              Logic: sum = sum + (counter * 3) for counter = 5 down to 1

.text
.globl _start

_start:
    li      x1, 5           # x1 = loop counter (starts at 5)
    li      x2, 0           # x2 = accumulative sum (result)
    li      x3, 3           # x3 = constant multiplier

loop_start:
    # Dependency chain start
    mul     x4, x1, x3      # x4 = x1 * 3 (Example: 5 * 3 = 15)
                            # x4 is produced here

    add     x2, x2, x4      # x2 = x2 + x4 (accumulate result)
                            # x2 depends on previous value of x2
                            # x2 depends on x4 immediately produced by MUL

    addi    x1, x1, -1      # Decrement loop counter
                            # x1 depends on previous x1

    bne     x1, x0, loop_start  # Branch if x1 != 0
                                # depends on x1 produced by ADDI

    # End of test
    # Final result in x2 should be:
    # (5*3) + (4*3) + (3*3) + (2*3) + (1*3) = 15 + 12 + 9 + 6 + 3 = 45
    nop
    nop