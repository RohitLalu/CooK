# Encryption code and laptop link

> **Status: OPEN** (2026-11-16). Code complete; known-answer tests, the crypto runs, the link and the live-demo top all pass in simulation. Open, and only closable on the board: not run there, and `laptop.py` never run against a real serial port.

The three-core cryptography demonstration, and the optional live link to a
laptop. All C, RV32I only: no multiplier, no FPU, no custom instructions.

| Folder / file | What it is |
|---|---|
| `crypto/` | SHA-256, AES-128, the WOTS one-time signature, the mailbox protocol (`proto.h`), and the three core programs: `core0_arbiter.c` (keys and arbiter), `core1_aes.c`, `core2_sign.c`. `host_test.c` runs known-answer tests on the laptop |
| `run_crypto.py` | Builds the three programs and simulates them on the NoC and on the single bus, healthy and with one fault. `--board` builds the full-size board images |
| `link/` | The laptop link: `core0_link.c` (core 0's program) and `laptop.py` (the laptop's side) |
| `rtl/` | Hardware for the live demo only: `nexys4ddr_live_top.v` (the board top to select for the demo), `uart_port.v` (serial port on core 0) and `seven_seg_text.v` (text on the display). The normal board top needs none of these |
| `tb/tb_link.v`, `run_link_sim.py` | Simulation of the link, with the testbench playing the laptop |

```
cc -o /tmp/crypto_host crypto/host_test.c crypto/sha256.c crypto/aes128.c crypto/wots.c && /tmp/crypto_host
python3 encryption_code/run_crypto.py        # from the repo root; about 40 minutes
python3 encryption_code/run_link_sim.py      # about 10 minutes
python3 encryption_code/run_link_sim.py --top   # the same through the live-demo board top, about 25 minutes
```

The runners use the benchmark helpers and C runtime in `benchmarks/`
(`cooklib.py`, `crt/`). Results go to `benchmarks/results/crypto.md`; board
images to `benchmarks/build/`. What to expect on the board, and the limits to
state when presenting, are in `demo_tests/README.md`.
