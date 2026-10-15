# hammer.S -- contention load for the mesh test. Position independent, so the
# same image runs on any tile.
#
# 16 times: remote read of tile 3's ID register (returns 3), add it to a sum,
# and post the running sum as a remote write into tile 3's memory at
# 0x300 + 4*my_id. Then store the sum and a completion marker locally.
# Expected: sum = 48 on every tile running this image, and tile 3's memory
# holds 48 in each runner's slot. Several tiles running this at once force
# packets from different sources onto shared outputs, which is exactly the
# case the router's output lock exists for.
.section .text
.globl _start
_start:
    auipc s0, 0
    srli  s0, s0, 12
    slli  s0, s0, 12         # s0 = my tile base (PC rounded down to 4KB)
    srli  s4, s0, 12         # s4 = my tile id
    slli  s4, s4, 2
    li    s1, 0x00003000     # tile 3 base
    add   s5, s1, s4         # s5 = tile 3 base + 4*id
    li    s2, 16             # iterations
    li    s3, 0              # running sum
loop:
    lw    t0, 0(s1)          # REMOTE READ: tile 3 ID register
    add   s3, s3, t0
    sw    s3, 0x300(s5)      # REMOTE POSTED WRITE into tile 3 memory
    addi  s2, s2, -1
    bnez  s2, loop
    sw    s3, 0x200(s0)      # local result
    li    t1, 0x0000C0DE
    sw    t1, 0x204(s0)      # local completion marker
done:
    j     done
