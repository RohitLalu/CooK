# alltoall.S -- every tile tests every other tile through the network, all
# tiles at once. Position independent and mesh-size independent: the same
# image runs on every tile of any mesh (it reads the tile count from CSR 0x00C).
#
# For each other tile T (my_id+1, my_id+2, ... modulo the tile count):
#   1. remote read of T's ID register                         -> must equal T
#   2. remote read of T's tile-count register                 -> must equal N
#   3. word write then read back (read-after-write)           -> same word
#   4. four remote byte stores, then lw / lb / lbu / lh / lhu  -> every lane right
#   5. two remote halfword stores, then lw                    -> both halves right
#   6. walking ones and walking zeros, 32 bits each           -> 64 round trips
#   7. call a function that lives in T's memory (remote instruction fetch);
#      it returns the tile its own code is executing from     -> must equal T
#   = 74 checks per other tile.
#
# Memory use inside every tile's 4KB region:
#   0x000-0x0FF  CSRs
#   0x100-0x7FF  this program (must stay below 0x800)
#   0x800+64*S   16-word scratch slot written by source tile S (S < 16)
#   0xF00        error count     0xF04  completion marker 0xC0DE
#   0xF08        check count
# Software status CSR (0x008) while running: 0x52550000 ("RU"),
#   at the end: 0x600D0000 | checks on pass, 0xFA110000 | errors on failure.

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
    srli  s0, s0, 12
    slli  s0, s0, 12         # s0 = my tile base
    srli  s1, s0, 12         # s1 = my id
    lw    s2, 0xC(s0)        # s2 = number of tiles (local CSR)
    li    s3, 0              # errors
    li    s8, 0              # checks
    li    t0, 0x52550000
    sw    t0, 8(s0)          # status: running

    li    s4, 1              # k = 1 .. N-1
outer:
    bge   s4, s2, finish
    add   s5, s1, s4         # target = (id + k) mod N
    blt   s5, s2, 1f
    sub   s5, s5, s2
1:
    slli  s6, s5, 12         # s6 = target base
    slli  t0, s1, 6
    add   s7, s6, t0
    li    t1, 0x800
    add   s7, s7, t1         # s7 = my slot inside the target

    # 1. remote ID register
    lw    t0, 0(s6)
    CHECK t0, s5
    # 2. remote tile-count register
    lw    t0, 0xC(s6)
    CHECK t0, s2

    # 3. word read-after-write
    slli  t2, s1, 24
    slli  t3, s5, 16
    or    t2, t2, t3
    li    t3, 0xA5A5
    or    t2, t2, t3
    sw    t2, 0(s7)
    lw    t0, 0(s7)
    CHECK t0, t2

    # 4. byte lanes: bytes {0x80|id, 0x11, 0xC3, 0x7E} at slot+4..7
    ori   t3, s1, 0x80
    sb    t3, 4(s7)
    li    t3, 0x11
    sb    t3, 5(s7)
    li    t3, 0xC3
    sb    t3, 6(s7)
    li    t3, 0x7E
    sb    t3, 7(s7)
    li    t2, 0x7EC31180
    or    t2, t2, s1
    lw    t0, 4(s7)
    CHECK t0, t2
    li    t2, -128           # lb sign-extends 0x80|id
    or    t2, t2, s1
    lb    t0, 4(s7)
    CHECK t0, t2
    ori   t2, s1, 0x80       # lbu zero-extends
    lbu   t0, 4(s7)
    CHECK t0, t2
    li    t2, 0x7EC3         # lh of the upper half
    lh    t0, 6(s7)
    CHECK t0, t2
    li    t2, 0x1180         # lhu of the lower half
    or    t2, t2, s1
    lhu   t0, 4(s7)
    CHECK t0, t2

    # 5. halfword stores: 0xBEEF at slot+8, (id<<8)|0x5A at slot+10
    li    t3, 0xBEEF
    sh    t3, 8(s7)
    slli  t4, s1, 8
    ori   t4, t4, 0x5A
    sh    t4, 10(s7)
    slli  t2, t4, 16
    or    t2, t2, t3
    lw    t0, 8(s7)
    CHECK t0, t2

    # 6. walking ones and walking zeros at slot+12
    li    t5, 1
walk:
    sw    t5, 12(s7)
    lw    t0, 12(s7)
    CHECK t0, t5
    not   t6, t5
    sw    t6, 12(s7)
    lw    t0, 12(s7)
    CHECK t0, t6
    slli  t5, t5, 1
    bnez  t5, walk

    # 7. remote instruction fetch: call remote_fn inside the target's copy
    lla   t0, remote_fn
    sub   t0, t0, s0
    add   t0, t0, s6
    jalr  ra, 0(t0)
    CHECK a0, s5

    addi  s4, s4, 1
    j     outer

finish:
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

# Runs from whichever tile's memory it is fetched from: returns that tile's id.
remote_fn:
    auipc a0, 0
    srli  a0, a0, 12
    ret
