/* tile.ld -- memory layout of one tile for C programs.
 *
 *   base + 0x000  CSRs (not memory)
 *   base + 0x100  reset stub (crt0.S)
 *   base + 0x800  mailbox, 0x700 bytes: the remote write window. Other tiles
 *                 may write here and nowhere else (ni.v WIN_LO/WIN_HI), so
 *                 nothing of the program lives here. Layout: tile.h.
 *   base + 0x1000 code, constants, data, bss
 *   top of tile   stack, growing down
 *
 * The build passes TILE_BASE and TILE_SIZE with --defsym. Tiles must be
 * built with NOC_OFFSET_BITS >= 14 for any real C program (64 KB = 16).
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
    __tile_base = TILE_BASE;
    . = TILE_BASE + 0x100;
    .init : { KEEP(*(.text.init)) }
    ASSERT(. <= TILE_BASE + 0x800, "reset stub runs into the mailbox")

    . = TILE_BASE + 0x1000;
    .text   : { *(.text*) }
    .rodata : { *(.rodata*) *(.srodata*) }
    . = ALIGN(4);
    .data   : {
        __global_pointer$ = . + 0x800;
        *(.sdata*) *(.data*)
    }
    . = ALIGN(4);
    __bss_start = .;
    .bss    : { *(.sbss*) *(.bss*) *(COMMON) }
    . = ALIGN(4);
    __bss_end = .;
    __heap_start = .;
    __stack_top = TILE_BASE + TILE_SIZE;
    ASSERT(__bss_end + 0x400 <= __stack_top, "program leaves less than 1 KB of stack")
    /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.note*) *(.eh_frame*) }
}
