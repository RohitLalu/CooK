#!/bin/sh
# Builds the baremetal images as full-memory $readmemh files (.mem): one
# 32-bit word per line, MEM_WORDS lines, the program placed at word 64 (byte
# offset 0x100, because 0x000-0x0FF of every tile region are CSRs), every
# other word zero. The same file serves simulation and FPGA block-RAM init.
#
#   sw/<program>.mem     one image per program
#   sw/tileNN.mem        what tile NN runs on the FPGA (FPGA_PROG on every tile)
#
# Environment overrides:
#   MEM_WORDS   words per tile memory, = 2**(NOC_OFFSET_BITS-2)   (1024)
#   NUM_TILES   tiles in the mesh, = NOC_MESH_X*NOC_MESH_Y            (4)
#   FPGA_PROG   program loaded on every tile for the board            (alltoall)
set -e
cd "$(dirname "$0")"
CC=riscv64-unknown-elf-gcc
OC=riscv64-unknown-elf-objcopy
MEM_WORDS=${MEM_WORDS:-1024}
NUM_TILES=${NUM_TILES:-4}
FPGA_PROG=${FPGA_PROG:-alltoall}

for f in tile0 spin hammer alltoall; do
    $CC -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles \
        -Wl,-Ttext=0x100 -Wl,--build-id=none -o $f.elf $f.S
    $OC -O binary $f.elf $f.bin
    python3 -I -c "
import sys, struct
name, words = sys.argv[1], int(sys.argv[2])
d = open(name + '.bin', 'rb').read()
d += b'\0' * ((-len(d)) % 4)
prog = [w for (w,) in struct.iter_unpack('<I', d)]
room = words - 64
if len(prog) > room:
    sys.exit('%s: program is %d words, only %d fit after the CSR block' % (name, len(prog), room))
img = [0] * 64 + prog + [0] * (room - len(prog))
open(name + '.mem', 'w').write(''.join('%08x\n' % w for w in img))
print('  %s.mem  (%d program words, %d total)' % (name, len(prog), words))
" $f $MEM_WORDS
done

i=0
while [ $i -lt $NUM_TILES ]; do
    n=$(printf "%02d" $i)
    cp $FPGA_PROG.mem tile$n.mem
    i=$((i + 1))
done
echo "  tile00..tile$(printf "%02d" $((NUM_TILES - 1))).mem = $FPGA_PROG (FPGA images)"
