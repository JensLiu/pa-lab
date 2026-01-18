# Simple Recursive Fibonacci Test Case
#
# This program calculates fib(3) recursively.
# It is designed to be minimal to help debug control flow and stack issues.
#
# fib(0) = 0
# fib(1) = 1
# fib(n) = fib(n-1) + fib(n-2)
#
# Expected Execution Trace for fib(3):
# fib(3)
#   -> fib(2)
#       -> fib(1) returns 1
#       -> fib(0) returns 0
#       returns 1
#   -> fib(1) returns 1
#   returns 2

.section .text.init
.global _start

_start:
    # 1. Initialize Stack Pointer
    lui sp, %hi(_stack_top)
    addi sp, sp, %lo(_stack_top)

    # 2. Call fib(3)
    li a0, 3
    call fib

    # 3. Spin forever (a0 should be 2)
done:
    j done

# -----------------------------------------
# fib function
# a0 = n (input)
# a0 = fib(n) (output)
# -----------------------------------------
fib:
    # Base Case Check: if n <= 1, return n
    li t0, 1
    ble a0, t0, fib_return

    # Recursive Step
    # Stack Frame:
    #   0(sp): saved ra
    #   4(sp): saved s0 (preserves n)
    #   8(sp): saved s1 (preserves result of fib(n-1))
    addi sp, sp, -16
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)

    # Move n to s0
    mv s0, a0

    # First Recursive Call: fib(n-1)
    addi a0, s0, -1
    call fib
    
    # Save result of first call to s1
    mv s1, a0

    # Second Recursive Call: fib(n-2)
    addi a0, s0, -2
    call fib

    # Add results: fib(n-1) + fib(n-2)
    add a0, s1, a0

    # Restore registers and return
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

fib_return:
    ret
