ENTRY(_start) /* Specify the entry point from start.S */

/* Our device only have RAM */
MEMORY
{
    RAM   (wx) : ORIGIN = 0x00001000, LENGTH = 64K
}

/* Define the top of the stack at the end of RAM */
_stack_top = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
    /* Put startup code and all .text (code) in RAM */
    .text :
    {
        KEEP(*(.text.init)) /* Keep our _start function first */
        *(.text*)
    } > RAM

    /* Put read-only data in RAM */
    .rodata :
    {
        *(.rodata*)
    } > RAM

    /* Put .bss (uninitialized data) in RAM */
    .bss :
    {
        __bss_start = .; /* Symbol for start.S */
        *(.bss*)
        *(COMMON)
        __bss_end = .;   /* Symbol for start.S */
    } > RAM
    
    /* Note: This simple script doesn't handle initialized
    global data (.data) correctly. It's fine for this
    example, which has none.
    */
}