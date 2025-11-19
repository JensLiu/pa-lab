.section .text
.globl _start
_start:
# parameter TEST_MEMORY = 0x00000005
li  s0, 0x5          # S0 = TEST_MEMORY

# store value
li  t1, 123          # T1 = 123
li  t2, 234          # T2 = 234
sw  t1, 0(s0)        # memory[S0 + 0] = 123
sw  t2, 4(s0)        # memory[S0 + 4] = 234

# create dependency
li  t1, 345          # T1 = 345
li  t2, 456          # T2 = 456
lw  t1, 4(s0)        # T1 = memory[S0 + 4] -> 234
lw  t2, 0(s0)        # T2 = memory[S0 + 0] -> 123

# should stall one cycle for T2 (load); then:
add t1, t1, t2       # T1 = 234 + 123 = 357

# end of program (no syscall in simulation)
nop