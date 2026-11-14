# Three-core crypto demo on both architectures

Core 0: keys and arbiter. Core 1: AES-128 encrypt, then decrypt. Core 2: WOTS
signature (simulation size: `WOTS_LOGW=2`, `WOTS_N=1`). Pass means core 0 got the
plaintext back from the decrypt, the signature verified, and a changed message was
rejected.

| Arch | Result | Cycles | Core 0 status | Core 1 status | Core 2 status | Flits on the interconnect |
|---|---|---|---|---|---|---|
| noc, healthy | pass | 3052291 | 600d2806 | 600d0002 | 600d0001 | 280 |
| bus, healthy | pass | 3052292 | 600d2806 | 600d0002 | 600d0001 | 280 |
| noc, link 0-1 dead | pass | 3052275 | 600d2806 | 600d0002 | 600d0001 | 280 |
| bus, arbiter stuck | FAIL 0008 | 4786 | fa110008 | - | - | 0 |
