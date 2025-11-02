.section .text.init
.global _start

_start:
    # 1. Set up the stack pointer.
    # The symbol _stack_top is defined in our linker.ld
    lui sp, %hi(_stack_top)
    addi sp, sp, %lo(_stack_top)

    # 2. Clear the .bss section (zero-initialized global variables)
    # The symbols are defined in linker.ld
    lui a0, %hi(__bss_start)
    addi a0, a0, %lo(__bss_start)
    lui a1, %hi(__bss_end)
    addi a1, a1, %lo(__bss_end)

clear_bss_loop:
    beq a0, a1, bss_cleared
    sw zero, 0(a0)
    addi a0, a0, 4
    j clear_bss_loop

bss_cleared:
    # 3. Call main
    call main

    # 4. Infinite loop if main ever returns
_hang:
    j _hang