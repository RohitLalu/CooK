#!/bin/sh
# Builds the baremetal images and emits one 32-bit word per line of hex,
# which is what $readmemh wants. Text is linked at 0x100 because offsets
# 0x000-0x0FF of every tile region are CSRs, not memory.
set -e
cd "$(dirname "$0")"
CC=riscv64-unknown-elf-gcc
OC=riscv64-unknown-elf-objcopy
for f in tile0 spin hammer; do
    $CC -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles \
        -Wl,-Ttext=0x100 -Wl,--build-id=none -o $f.elf $f.S
    $OC -O binary $f.elf $f.bin
    python3 -I -c "
import sys,struct
d=open('$f.bin','rb').read()
d+=b'\0'*((-len(d))%4)
print('\n'.join('%08x'%w for (w,) in struct.iter_unpack('<I',d)))
" > $f.hex.raw; python3 -I -c "
import sys
w=[l.strip() for l in open(sys.argv[1]) if l.strip()]
w+=['00000000']*(64-len(w))
open(sys.argv[2],'w').write('\n'.join(w[:64])+'\n')
" $f.hex.raw $f.hex; rm -f $f.hex.raw
    echo "  $f.hex  ($(wc -l < $f.hex | tr -d ' ') words)"
done
