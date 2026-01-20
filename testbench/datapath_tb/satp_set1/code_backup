# Test SATP CSR setting: unprivileged instructions before and after SATP write
# 
# Scenario: Test pipeline behavior when SATP is modified mid-execution
# This tests that:
#   1. Instructions in flight before SATP write complete correctly
#   2. SATP write commits properly
#   3. Instructions after SATP write execute correctly
#   4. No pipeline hazards or stalls cause incorrect behavior
#
# SATP Register Format (RV32 Sv32):
#   [31]     MODE  - 0=Bare (no translation), 1=Sv32
#   [30:22]  ASID  - 9-bit Address Space Identifier
#   [21:20]  unused (2 bits)
#   [19:0]   PPN   - 20-bit Physical Page Number of root page table
#
# CSR Address for SATP: 0x180

.equ SATP_CSR, 0x180

.section .text
.globl _start
_start:
    #==========================================================
    # Phase 1: Unprivileged instructions BEFORE SATP write
    # These should all complete normally with SATP=0 (BARE mode)
    #==========================================================
    
    # ALU operations - build up some values
    li      t0, 100             # t0 = 100
    li      t1, 200             # t1 = 200
    add     t2, t0, t1          # t2 = 300
    sub     t3, t1, t0          # t3 = 100
    slli    t4, t0, 2           # t4 = 400
    srli    t5, t1, 1           # t5 = 100
    and     t6, t0, t1          # t6 = 64 (0x64 & 0xC8 = 0x40)
    or      s0, t0, t1          # s0 = 236 (0x64 | 0xC8 = 0xEC)
    xor     s1, t0, t1          # s1 = 172 (0x64 ^ 0xC8 = 0xAC)
    
    # More computation to fill pipeline
    addi    s2, t2, 50          # s2 = 350
    addi    s3, t3, 25          # s3 = 125
    mul     s4, t0, t1          # s4 = 20000 (if MUL supported)
    
    #==========================================================
    # Phase 2: SET SATP - This is the critical transition point
    # Setting SATP to BARE mode (MODE=0) - no address translation
    # Pipeline must handle this CSR write correctly
    #==========================================================
    
    li      a0, 0x00000000      # BARE mode configuration
    csrw    SATP_CSR, a0        # Write SATP
    
    #==========================================================
    # Phase 3: Unprivileged instructions AFTER SATP write
    # These execute after SATP has been set to BARE mode
    #==========================================================
    
    # Continue computations - verify pipeline didn't corrupt state
    add     s5, s2, s3          # s5 = 475 (350 + 125)
    sub     s6, s2, s3          # s6 = 225 (350 - 125)
    sll     s7, t0, t1          # shift (implementation dependent)
    
    # Read back SATP to verify write succeeded
    csrr    a1, SATP_CSR        # a1 should be 0x00000000
    
    #==========================================================
    # Phase 4: More unprivileged ops, then another SATP write
    # Now enable Sv32 mode
    #==========================================================
    
    # More ALU operations
    addi    s8, s5, 100         # s8 = 575
    addi    s9, s6, 50          # s9 = 275
    add     s10, s8, s9         # s10 = 850
    
    # Set SATP to Sv32 mode with ASID=1, PPN=0x1000
    # Value: 0x80000000 | (1 << 22) | 0x1000 = 0x80401000
    lui     a2, 0x80401         # a2 = 0x80401000
    csrw    SATP_CSR, a2        # Enable Sv32 translation
    
    #==========================================================
    # Phase 5: Instructions after enabling Sv32
    # (In BARE mode these still work; with actual VM they'd need valid page tables)
    #==========================================================
    
    # More unprivileged computation
    addi    s11, s10, 150       # s11 = 1000
    add     t0, s11, s8         # t0 = 1575
    sub     t1, s11, s9         # t1 = 725
    
    # Verify SATP was set correctly
    csrr    a3, SATP_CSR        # a3 should be 0x80401000
    
    #==========================================================
    # Phase 6: Rapid sequence - unprivileged, SATP, unprivileged
    # Tests back-to-back transitions
    #==========================================================
    
    add     t2, t0, t1          # t2 = 2300
    addi    t3, t2, 1           # t3 = 2301
    
    # Quick SATP change - switch ASID
    # ASID=2, same PPN: 0x80000000 | (2 << 22) | 0x1000 = 0x80801000
    lui     a4, 0x80801         # a4 = 0x80801000
    csrw    SATP_CSR, a4
    
    addi    t4, t3, 1           # t4 = 2302 (immediately after CSR write)
    addi    t5, t4, 1           # t5 = 2303
    addi    t6, t5, 1           # t6 = 2304
    
    csrr    a5, SATP_CSR        # a5 should be 0x80801000
    
    #==========================================================
    # Phase 7: Data dependency across SATP write
    # Register written before SATP, read after
    #==========================================================
    
    li      gp, 0xDEADBEEF      # gp = 0xDEADBEEF (before SATP write)
    addi    tp, gp, 1           # tp depends on gp
    
    # Change SATP again
    lui     a6, 0x80C01         # ASID=3, PPN=0x1000
    csrw    SATP_CSR, a6
    
    # Use values computed before SATP write
    add     a7, gp, tp          # a7 = 0xDEADBEEF + 0xDEADBEF0 (use pre-SATP values)
    
    #==========================================================
    # Phase 8: Switch back to BARE mode
    #==========================================================
    
    addi    t0, a7, 1           # computation before
    addi    t1, t0, 1
    
    csrw    SATP_CSR, zero      # Back to BARE mode (SATP = 0)
    
    addi    t2, t1, 1           # computation after
    addi    t3, t2, 1
    
    csrr    t4, SATP_CSR        # t4 should be 0x00000000
    
    #==========================================================
    # Phase 9: Multiple SATP writes in quick succession
    # Tests that each write takes effect
    #==========================================================
    
    lui     t5, 0x80400         # ASID=1
    csrw    SATP_CSR, t5
    nop                         # small gap
    
    lui     t5, 0x80800         # ASID=2
    csrw    SATP_CSR, t5
    nop
    
    lui     t5, 0x80C00         # ASID=3
    csrw    SATP_CSR, t5
    nop
    
    lui     t5, 0x81000         # ASID=4
    csrw    SATP_CSR, t5
    
    csrr    t6, SATP_CSR        # t6 should be 0x81000000 (last write wins)
    
    #==========================================================
    # Phase 10: Final verification sequence
    #==========================================================
    
    # Set final known value
    # MODE=1, ASID=0x55, PPN=0xABCDE
    # Value: 0x80000000 | (0x55 << 22) | 0xABCDE = 0x9540BCDE
    lui     s0, 0x9540B         # s0 = 0x9540B000
    ori     s0, s0, 0xCDE       # s0 = 0x9540BCDE
    
    # Some instructions before final SATP write
    li      s1, 1
    li      s2, 2
    li      s3, 3
    add     s4, s1, s2          # s4 = 3
    add     s5, s3, s4          # s5 = 6
    
    csrw    SATP_CSR, s0        # Final SATP write
    
    # Instructions after final SATP write
    add     s6, s4, s5          # s6 = 9
    add     s7, s5, s6          # s7 = 15
    add     s8, s6, s7          # s8 = 24
    
    # Final SATP readback
    csrr    s9, SATP_CSR        # s9 should be 0x9540BCDE
    
    # End markers
    li      s10, 0xCAFEBABE     # success marker
    li      s11, 0x12345678     # test complete marker
    
    # End of test
    nop
    nop
    nop
