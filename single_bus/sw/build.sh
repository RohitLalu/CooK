#!/bin/sh
# Builds the bus-only baremetal images as full-memory $readmemh files, in the
# same format as the NoC's sw/build.sh (program at word 64, MEM_WORDS lines).
# The images both architectures share (alltoall, hammer, ...) are built by
# ../../sw/build.sh and used from there.
set -e
cd "$(dirname "$0")"
CC=riscv64-unknown-elf-gcc
OC=riscv64-unknown-elf-objcopy
MEM_WORDS=${MEM_WORDS:-1024}

for f in ddr; do
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
