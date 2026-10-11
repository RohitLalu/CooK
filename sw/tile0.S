# tile0.S -- orchestrator tile.
#
# 1. Remote read of tile 3's status register. Tile 3's NI answers in hardware,
#    so tile 3's core does not need to be running anything.
# 2. Read of an address OUTSIDE the NoC window. This must come back as POISON
#    with the illegal flag latched -- NOT a hang. This is the case that makes
#    picorv32's default STACKADDR (0xffff_ffff) survivable instead of fatal.
# 3. Completion marker, then spin.
#
# Tile 0 region: 0x0000_0000..0x0000_0FFF  (0x000-0x0FF CSR, 0x100+ memory)
.section .text
.globl _start
_start:
    li   t0, 0x00003000      # tile 3, offset 0x000 = status/ID register
    lw   t1, 0(t0)           # REMOTE READ across two hops
    li   t2, 0x00000200
    sw   t1, 0(t2)

    li   t0, 0xFFFFF000      # outside the NoC window entirely
    lw   t1, 0(t0)           # must return POISON and set the illegal flag
    li   t2, 0x00000208
    sw   t1, 0(t2)

    li   t0, 0x00000004      # local CSR: error flags
    lw   t1, 0(t0)
    li   t2, 0x0000020C
    sw   t1, 0(t2)

    li   t2, 0x00000204
    li   t1, 0x0000C0DE
    sw   t1, 0(t2)           # completion marker
done:
    j    done
