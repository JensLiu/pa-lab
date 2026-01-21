# Store Buffer Partial Overlap Test 1
# Scenario: Store halfword, then immediately read word (partial overlap)
#
# The read is larger than the store, so it partially overlaps.
# CPU must wait for SB to drain before completing the read.

.section .text
.globl _start

_start:
    # Initialize base address
    li      sp, 0x00010000

    # First, fill memory with known pattern by storing words
    # These will go through SB -> cache over time
    li      t0, 0x12345678
    sw      t0, 0(sp)
    li      t0, 0xAAAAAAAA
    sw      t0, 4(sp)
    li      t0, 0xBBBBBBBB
    sw      t0, 8(sp)
    li      t0, 0xCCCCCCCC
    sw      t0, 12(sp)
    # Do some work to let SB drain
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    # Now store a halfword - this goes to SB
    li      t1, 0xABCD
    sh      t1, 0(sp)           # Overwrites lower 2 bytes at sp+0
    # SB entry: addr=sp, len=2, data=0xABCD
    
    # Immediately read full word - partial overlap!
    # Read wants [sp+0, sp+3], SB only has [sp+0, sp+1]
    lw      t2, 0(sp)
    
    # Expected: 0x1234ABCD (upper half from cache, lower half from drained store)
    li      t3, 0x1234ABCD
    bne     t2, t3, fail

    # Success
    li      a0, 1
    j       end

fail:
    li      a0, 0
end:
    j       end