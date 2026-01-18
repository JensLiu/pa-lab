# Test: Load After Jump
# Purpose: Test pipeline behavior when a load instruction immediately follows a jump
# The load should be flushed when the jump is taken, but the memory system may
# already have initiated the load request, which could confuse the memory stage

.text
.globl _start

_start:
    # Initialize test data in memory
    li x1, 0x1000          # Base address for test data
    li x2, 0xDEADBEEF      # Test pattern 1
    sw x2, 0(x1)           # Store test pattern at 0x1000
    li x3, 0xCAFEBABE      # Test pattern 2
    sw x3, 4(x1)           # Store test pattern at 0x1004
    
    # Initialize result register (should NOT be modified by flushed load)
    li x10, 0x12345678     # Expected result
    
    # Test case 1: Unconditional jump with load immediately after
    # The load at jump_target+4 should be flushed
    j jump_target
    lw x10, 0(x1)          # This load should be FLUSHED (not executed)
    
jump_target:
    # If the flushed load executed, x10 would be 0xDEADBEEF
    # If correct, x10 should still be 0x12345678
    li x11, 0x12345678     # Expected value
    bne x10, x11, test_failed
    
    # Test case 2: Conditional branch taken with load after
    li x10, 0xABCDEF00     # Reset result register
    li x4, 1
    li x5, 1
    beq x4, x5, branch_target  # Branch will be taken
    lw x10, 4(x1)          # This load should be FLUSHED
    
branch_target:
    # x10 should still be 0xABCDEF00, not 0xCAFEBABE
    li x11, 0xABCDEF00
    bne x10, x11, test_failed
    
    # Test case 3: Multiple loads after jump to stress store buffer
    li x10, 0x11111111
    li x20, 0x22222222
    li x21, 0x33333333
    j multi_load_target
    lw x10, 0(x1)          # Should be flushed
    lw x20, 4(x1)          # Should be flushed
    lw x21, 8(x1)          # Should be flushed
    
multi_load_target:
    # All registers should retain their initialized values
    li x11, 0x11111111
    bne x10, x11, test_failed
    li x11, 0x22222222
    bne x20, x11, test_failed
    li x11, 0x33333333
    bne x21, x11, test_failed
    
test_passed:
    li x28, 1              # Test passed indicator
    j end_test
    
test_failed:
    li x28, 0              # Test failed indicator
    
end_test:
    # Infinite loop to end simulation
    j end_test
