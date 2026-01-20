.section .text
.globl _start

# SATP CSR address = 0x180
# Test cases for SATP read/write operations
# Expected final result in a0

_start:
    # Initialize accumulator
    li      a0, 0           # a0 = accumulator for results

    #=========================================
    # Test 1: Basic write and read back
    #=========================================
    li      t0, 0x12345678
    csrw    satp, t0        # write 0x12345678 to SATP
    csrr    t1, satp        # read SATP back to t1
    add     a0, a0, t1      # accumulate: a0 += 0x12345678

    #=========================================
    # Test 2: Overwrite with new value
    #=========================================
    li      t0, 0xABCDEF00
    csrw    satp, t0        # overwrite SATP
    csrr    t1, satp        # read back
    add     a0, a0, t1      # accumulate: a0 += 0xABCDEF00

    #=========================================
    # Test 3: Edge case - all zeros
    #=========================================
    li      t0, 0x00000000
    csrw    satp, t0
    csrr    t1, satp
    add     a0, a0, t1      # accumulate: a0 += 0

    #=========================================
    # Test 4: Edge case - all ones
    #=========================================
    li      t0, 0xFFFFFFFF
    csrw    satp, t0
    csrr    t1, satp
    add     a0, a0, t1      # accumulate: a0 += 0xFFFFFFFF

    #=========================================
    # Test 5: Alternating pattern 0x55555555
    #=========================================
    li      t0, 0x55555555
    csrw    satp, t0
    csrr    t1, satp
    add     a0, a0, t1      # accumulate: a0 += 0x55555555

    #=========================================
    # Test 6: Alternating pattern 0xAAAAAAAA
    #=========================================
    li      t0, 0xAAAAAAAA
    csrw    satp, t0
    csrr    t1, satp
    add     a0, a0, t1      # accumulate: a0 += 0xAAAAAAAA

    #=========================================
    # Test 7: CSRRW - read old value while writing new
    # Write 0x11111111, then use csrrw to write 0x22222222
    # and capture the old value
    #=========================================
    li      t0, 0x11111111
    csrw    satp, t0        # SATP = 0x11111111
    li      t0, 0x22222222
    csrrw   t1, satp, t0    # t1 = old SATP (0x11111111), SATP = 0x22222222
    add     a0, a0, t1      # accumulate: a0 += 0x11111111

    # Verify the new value was written
    csrr    t1, satp        # should be 0x22222222
    add     a0, a0, t1      # accumulate: a0 += 0x22222222

    #=========================================
    # Test 8: Multiple consecutive reads (no hazard)
    #=========================================
    li      t0, 0x33333333
    csrw    satp, t0
    csrr    t1, satp
    csrr    t2, satp
    csrr    t3, satp
    add     a0, a0, t1      # accumulate: a0 += 0x33333333
    add     a0, a0, t2      # accumulate: a0 += 0x33333333
    add     a0, a0, t3      # accumulate: a0 += 0x33333333

    #=========================================
    # Test 9: Write-after-read dependency
    # Read SATP, modify, write back
    #=========================================
    li      t0, 0x00000100
    csrw    satp, t0        # SATP = 0x100
    csrr    t1, satp        # t1 = 0x100
    addi    t1, t1, 0x50    # t1 = 0x150
    csrw    satp, t1        # SATP = 0x150
    csrr    t2, satp        # t2 = 0x150
    add     a0, a0, t2      # accumulate: a0 += 0x150

    #=========================================
    # Test 10: Loop - write and read multiple times
    # Sum SATP values: 1 + 2 + 3 + 4 + 5 = 15 (0xF)
    #=========================================
    li      t0, 1           # counter
    li      t4, 5           # limit
    li      t5, 0           # local sum

loop_start:
    bgt     t0, t4, loop_end
    csrw    satp, t0        # SATP = counter
    csrr    t1, satp        # read back
    add     t5, t5, t1      # local sum += SATP
    addi    t0, t0, 1       # counter++
    j       loop_start

loop_end:
    add     a0, a0, t5      # accumulate: a0 += 15

    #=========================================
    # Final expected value calculation:
    # Test 1:  0x12345678
    # Test 2:  0xABCDEF00
    # Test 3:  0x00000000
    # Test 4:  0xFFFFFFFF
    # Test 5:  0x55555555
    # Test 6:  0xAAAAAAAA
    # Test 7a: 0x11111111
    # Test 7b: 0x22222222
    # Test 8:  0x33333333 * 3 = 0x99999999
    # Test 9:  0x00000150
    # Test 10: 0x0000000F
    #=========================================

    # End of program
    nop
    nop
    nop
