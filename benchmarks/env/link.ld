/* One tile's image: code from TEXT_BASE (the tile window + 0x100, set by the
   build with --defsym), data straight after it. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
    . = TEXT_BASE;
    .text : { *(.text.init) *(.text*) }
    . = ALIGN(16);
    .data : { *(.data*) *(.rodata*) *(.sdata*) *(.sbss*) *(.bss*) *(COMMON) }
    _end = .;
}
