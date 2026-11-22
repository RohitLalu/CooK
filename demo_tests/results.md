# Demo programs in simulation (NoC, 64 KB tiles)

| Demo | Result | Detail |
|---|---|---|
| Looping traffic, healthy, 40,000 cycles | pass | passes so far: 84, 84, 84 |
| Looping traffic, link 0→1 goes silent at cycle 20,000 (no reset) | pass | status fa11000c, fa11000b, 600d007f; NI flags 0021 |
| DMA to DDR and back with the lock, 3 cores × 3 rounds | pass | status 600d0003, 600d0003, 600d0003; 28614 cycles; gateway flags 000 |
| Parallel speed-up, 3 × 6 chained SHA-256 blocks | pass | one core 733675 cycles, three cores 254146 cycles: 2.89× faster; digests equal |
| Restart: core 1 traps, core 0 restarts it | pass | status 600d0001, 600d0002, 600d0000; core 1 running again (trap bits 000); 874 cycles |
| Fix 1, restart with core 1 cut off (links 0-1 and 2-3 dead) | pass | core 0 fa110003 after 3397 cycles (board, before the fix: fa110002 after 12.2 s) |
| Fix 1, restart with core 1 cut off (router 1 broken) | pass | core 0 fa110003 after 3397 cycles (board, before the fix: fa110002 after 12.2 s) |
| Fix 2b, restart after CPU_RESET (memory not reloaded) | pass | second run: core 0 600d0001, core 1 600d0002 (board, before: core 0 fa110001) |
| Fix 1, DMA with the gateway's router broken | pass | status fa110001, fa110001, fa110001 (board, before: fa110004) |
| Fix 1, DMA with links 0-1 and 2-3 dead (cores 0, 2 cut off from the gateway) | pass | status fa110001, 52550000, fa110001 (core 1 still reaches the gateway) |
| Fix 2a, speed-up after CPU_RESET with every link dead | pass | core 0 fa110002 (board, before: a false pass, 600d07d0) |
| DMA rate, DDR to tile, as the board program measures it | pass | 6.5 cycles per word, 30.8 MB/s at 50 MHz, including the per-transfer setup and polling |
| DMA rate, tile to DDR, as the board program measures it | pass | 18.5 cycles per word, 10.8 MB/s at 50 MHz, including the per-transfer setup and polling |
