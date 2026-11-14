# Dhrystone and CoreMark on both architectures

Each core runs the benchmark from its own tile memory (64 KB tiles, RV32I, `-O2`,
multiply and divide in software). Rates assume the board's 50 MHz clock.

| Benchmark | Arch | Cores | Result | Bytes | Cycles per iteration | Rate | Derived |
|---|---|---|---|---|---|---|---|
| dhrystone | noc | 3 | pass | 8420 | 3935 | 12706.84 Dhrystones/s | 7.232 DMIPS |
| dhrystone | bus | 3 | pass | 8420 | 3935 | 12706.83 Dhrystones/s | 7.232 DMIPS |
| coremark | noc | 1 | pass | 16412 | 4425633 | 11.30 CoreMark (iterations/s) | 0.226 CoreMark/MHz |
| coremark | bus | 1 | pass | 16412 | 4425633 | 11.30 CoreMark (iterations/s) | 0.226 CoreMark/MHz |
