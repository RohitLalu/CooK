# ddr.S -- every core uses the shared DDR through the bus at once. Position
# independent: the same image runs on every core tile.
#
# The memory node is the last node (kind CSR 0x010 = 2, see sb_mem_ni.v).
#   1. set my DDR_BASE to id << 20 (a private megabyte)
#   2. write 64 words {id, 0x5A, index} through the window, then read all 64 back
#   3. one byte store into word 0, then lw: only that byte changed
#   4. move DDR_BASE to the shared megabyte 15, write id+1 into slot id, read it back
#   = 66 checks. All three cores run this together, so every access contends
#   for the one bus and the one memory port.
# Results as in alltoall.S: 0xF00 errors, 0xF04 marker 0xC0DE, 0xF08 checks,
# status CSR 0x600D0000 | checks on pass, 0xFA110000 | errors on failure.

/* Tile size: a tile owns 2**TILE_SHIFT bytes (NOC_OFFSET_BITS of the build).
 * sw/build.sh passes it; 12 = the default 4 KB tiles. */
#ifndef TILE_SHIFT
#define TILE_SHIFT 12
#endif

.section .text
.globl _start

.macro CHECK got, exp
    addi  s8, s8, 1
    beq   \got, \exp, 99f
    addi  s3, s3, 1
99:
.endm

_start:
    auipc s0, 0
    srli  s0, s0, TILE_SHIFT
    slli  s0, s0, TILE_SHIFT         # s0 = my tile base
    srli  s1, s0, TILE_SHIFT         # s1 = my id
    lw    s2, 0xC(s0)        # s2 = number of nodes
    li    s3, 0              # errors
    li    s8, 0              # checks
    li    t0, 0x52550000
    sw    t0, 8(s0)          # status: running

    addi  t0, s2, -1
    slli  s4, t0, TILE_SHIFT         # s4 = memory node base
    addi  s5, s4, 0x200      # s5 = DDR window

    # 1. private megabyte
    slli  t0, s1, 20
    sw    t0, 0x20(s4)

    # 2. 64 words out, 64 words back
    slli  s6, s1, 24
    li    t0, 0x5A0000
    or    s6, s6, t0         # s6 = pattern base
    li    t1, 0
1:  slli  t2, t1, 2
    add   t2, t2, s5
    or    t3, s6, t1
    sw    t3, 0(t2)
    addi  t1, t1, 1
    li    t4, 64
    blt   t1, t4, 1b
    li    t1, 0
2:  slli  t2, t1, 2
    add   t2, t2, s5
    or    t3, s6, t1
    lw    t0, 0(t2)
    CHECK t0, t3
    addi  t1, t1, 1
    li    t4, 64
    blt   t1, t4, 2b

    # 3. byte store into word 0 (which holds s6)
    li    t3, 0xC3
    sb    t3, 1(s5)
    li    t2, 0xC300
    or    t2, t2, s6
    lw    t0, 0(s5)
    CHECK t0, t2

    # 4. shared megabyte, one slot per core
    li    t0, 0x00F00000
    sw    t0, 0x20(s4)
    slli  t2, s1, 2
    add   t2, t2, s5
    addi  t3, s1, 1
    sw    t3, 0(t2)
    lw    t0, 0(t2)
    CHECK t0, t3

    li    t0, 0xF00
    add   t0, t0, s0
    sw    s3, 0(t0)          # error count
    sw    s8, 8(t0)          # check count
    bnez  s3, failed
    li    t1, 0x600D0000
    or    t1, t1, s8
    j     report
failed:
    li    t1, 0xFA110000
    or    t1, t1, s3
report:
    sw    t1, 8(s0)          # status CSR
    li    t1, 0x0000C0DE
    sw    t1, 4(t0)          # completion marker
done:
    j     done
