# Demo programs in simulation (NoC, 64 KB tiles)

| Demo | Result | Detail |
|---|---|---|
| Looping traffic, healthy, 40,000 cycles | pass | passes so far: 84, 84, 84 |
| Looping traffic, link 0→1 goes silent at cycle 20,000 (no reset) | pass | status fa11000b, fa11000b, 600d007f; NI flags 0021 |
| DMA to DDR and back with the lock, 3 cores × 3 rounds | pass | status 600d0003, 600d0003, 600d0003; 28141 cycles; gateway flags 000 |
| Parallel speed-up, 3 × 6 chained SHA-256 blocks | pass | one core 733654 cycles, three cores 254027 cycles: 2.89× faster; digests equal |
