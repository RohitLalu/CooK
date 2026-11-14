# crt0.S -- start-up code for C programs on a CooK tile (either architecture).
#
# The core resets to tile base + 0x100 with sp already at the top of the tile
# (PROGADDR_RESET / STACKADDR in mesh_top.v and sb_top.v). The reset stub
# jumps over the mailbox window (0x800..0xEFF, the only part of a tile other
# tiles may write) to the program at 0x1000: see tile.ld.
#
# main()'s return value becomes the tile's status word (CSR 0x008), the
# convention every CooK program uses: 0 -> 0x600D0000 (pass), anything else
# -> 0xFA110000 | value (fail). A program may also write the CSR itself
# (tile_report() in tile.h) and never return.

#undef main      /* a port may rename a benchmark's main with -Dmain=...; not ours */

    .section .text.init
    .globl _start
_start:
    j     _cstart

    .section .text
    .globl _cstart
_cstart:
    .option push
    .option norelax
    la    gp, __global_pointer$
    .option pop
    la    t0, __bss_start
    la    t1, __bss_end
1:  bgeu  t0, t1, 2f
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     1b
2:  call  main
    la    t0, __tile_base
    lui   t1, 0x600D0
    beqz  a0, 3f
    lui   t1, 0xFA110
    slli  a0, a0, 16
    srli  a0, a0, 16
    or    t1, t1, a0
3:  sw    t1, 8(t0)
4:  j     4b
