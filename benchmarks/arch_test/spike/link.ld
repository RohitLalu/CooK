/* Spike: program at 0x80000000, the address its boot ROM jumps to. */
OUTPUT_ARCH(riscv)
ENTRY(rvtest_entry_point)
SECTIONS
{
    . = 0x80000000;
    .text.init : { *(.text.init) }
    . = ALIGN(0x1000);
    .tohost : { *(.tohost) }
    . = ALIGN(0x1000);
    .text : { *(.text*) }
    . = ALIGN(0x1000);
    .data : { *(.data*) *(.rodata*) *(.sdata*) *(.sbss*) *(.bss*) }
    _end = .;
}
