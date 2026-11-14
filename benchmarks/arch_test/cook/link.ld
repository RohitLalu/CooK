/* One tile: code from TEXT_BASE (tile window + 0x100), data after it. */
OUTPUT_ARCH(riscv)
ENTRY(rvtest_entry_point)
SECTIONS
{
    . = TEXT_BASE;
    .text : { *(.text.init) *(.text*) }
    . = ALIGN(16);
    .data : { *(.data*) *(.rodata*) *(.sdata*) *(.sbss*) *(.bss*) }
    _end = .;
}
