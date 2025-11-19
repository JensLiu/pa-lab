    .section .text
    .global  _start

# instruction cache of 8 sets
# 128-bit per cache line (4 words or instructions per line)
# needs 32 consecutive instructions (including the jmp) to fill the whole cache
# assume the jmp instruction is at A
# want to construct that
# 1. IF is fetching A + 1 and there is a cache miss
# -> IF is waiting for cache response (which takes more than 1 cycle)
# 2. EX wants to jump because it detected an branch
# => Want: EX waits until IF have fetched the "wrongly-predicted" A + 1 instruction
# After IF finishes, EX can then inform IF to jump

_start:
    # Initialize registers
    addi x1, x0, 1
    addi x2, x0, 1
    addi x3, x0, 0

    # Align to cache line boundary (16 bytes)
    .balign 16

    # Fill the cache (8 sets, 32 instructions)
    # We execute 31 instructions (0-30) to fill sets 0-7 partially.
    # The 32nd instruction (index 31) will be the branch.
    
    # Set 0
    nop
    nop
    nop
    nop
    
    # Set 1
    nop
    nop
    nop
    nop
    
    # Set 2
    nop
    nop
    nop
    nop
    
    # Set 3
    nop
    nop
    nop
    nop
    
    # Set 4
    nop
    nop
    nop
    nop
    
    # Set 5
    nop
    nop
    nop
    nop
    
    # Set 6
    nop
    nop
    nop
    nop
    
    # Set 7
    nop
    nop
    nop
    # Instruction 31 (Index 31). End of Set 7.
    # Next instruction (Index 32) maps to Set 0.
    beq x1, x2, target

    # Instruction 32 (Index 32). Start of Set 0.
    # This should cause a conflict miss with Set 0 (which holds Line 0).
    # IF should stall here.
    addi x3, x0, 100  # Should NOT execute
    nop
    nop
    nop

target:
    # Branch target
    addi x10, x0, 1   # Success indicator
    
    # Loop forever to consume remaining cycles
loop:
    j loop
