# Three-core crypto demo on both architectures

Core 0: keys and arbiter. Core 1: AES-128 encrypt, then decrypt. Core 2: WOTS
signature (simulation size: `WOTS_LOGW=2`, `WOTS_N=1`). Pass means core 0 got the
plaintext back from the decrypt, the signature verified, a changed message was
rejected, core 0 could not read core 1's private memory (remote read window on),
and core 1 ignored a job whose keyed checksum was wrong.

| Arch | Result | Cycles | Core 0 status | Core 1 status | Core 2 status | Flits on the interconnect |
|---|---|---|---|---|---|---|
| noc, healthy | pass | 4517881 | 600d2806 | 600d0002 | 600d0001 | 328 |
| bus, healthy | pass | 4517882 | 600d2806 | 600d0002 | 600d0001 | 328 |
| noc, link 0-1 dead | pass | 4517897 | 600d2806 | 600d0002 | 600d0001 | 328 |
| bus, arbiter stuck | FAIL 0008 | 5088 | fa110008 | - | - | 0 |
