# FPGA demos: status

> **Status: OPEN** (2026-11-16). Every item is built and passes in simulation, including the live-demo top. Open, and only closable on the board: none has run there, and `laptop.py` has not been run against a real serial port.

Goal: show on the board that the computation happens in the FPGA's NoC, on
three cores at once, and not on the laptop.

Everything that was planned in this file is now built and passes in
simulation. **None of it has run on the board yet**: it all needs a bitstream
with 64 KB tiles (`NOC_OFFSET_BITS=16`), which has not been built. What to
expect on the board for each demo is in `demo_tests/README.md`.

| Planned | Status | Where |
|---|---|---|
| Crypto on three cores: keys and arbiter, AES-128, signature | Built, simulated on NoC and bus | `encryption_code/crypto/`, `encryption_code/run_crypto.py` |
| The same with a fault: NoC survives, bus does not | Built, simulated | the same runner, fault cases |
| Laptop link: decrypt and show, encrypt and return | Built, simulated with the testbench as the laptop | `encryption_code/link/`, `encryption_code/run_link_sim.py` |
| Serial port on core 0 | Built, optional | `encryption_code/rtl/uart_port.v` |
| A separate top module for the live demo | Built, simulated as built (`run_link_sim.py --top`): real baud rate, text read from the display pins | `encryption_code/rtl/nexys4ddr_live_top.v` |
| Text on the 7-segment display | Built | `encryption_code/rtl/seven_seg_text.v` |
| Laptop script | Built; its AES self-checked, never run against a board | `encryption_code/link/laptop.py` |
| Looping traffic, so a fault switched in while running is visible | Built, simulated | `demo_tests/programs/loop_traffic.c` |
| Parallel speed-up | Built, simulated (2.89× with three cores) | `demo_tests/programs/speedup.c` |
| DMA to DDR and back | Built, simulated with the DMA model | `demo_tests/programs/dma_lock.c` |
| Lock contention | Built, simulated (same program on three cores) | the same |
| Dhrystone on three cores | Built, simulated | `benchmarks/run_c_benchmarks.py` |
| Restart a stopped core (added later) | Built, simulated | `demo_tests/programs/restart.c` |

## How the serial port is attached

There are two board tops.

- `rtl/board/nexys4ddr/nexys4ddr_top.v` is the normal one. It contains no
  serial port and needs no file from `encryption_code/`.
- `encryption_code/rtl/nexys4ddr_live_top.v` is the live-demo top. It is the
  normal top with the serial port on core 0, the text display and the remote
  read window switched on.

For the live demo, make `nexys4ddr_live_top` the synthesis top, add the three
files in `encryption_code/rtl/`, define `NOC_OFFSET_BITS=16`, and use the
images from `python3 encryption_code/run_link_sim.py --board`. The serial
port sits on core 0's memory bus in front of its network interface and
answers one page of addresses; the network interface is not changed.

## Decisions taken along the way

- **Signature scheme: WOTS over SHA-256, not ML-DSA.** ML-DSA needs more
  working memory than a tile holds and is dominated by multiplication, which
  these cores do in software.
- **AES-128 only.** AES-256 is not written.
- **The key is compiled into both sides.** This is not a key exchange.
- **Mailbox messages carry a keyed checksum, in firmware.**

## Why this shows the FPGA did the work

- In `show` mode the laptop sends ciphertext only; the plaintext appears on
  the board's own display.
- Core 0 has no AES code, so the answer crossed the NoC to core 1 and back.
- With a fault switch set and a reset, it still works; the single-bus build
  with its fault switch does not.

## Still to do

- Build a 64 KB-tile bitstream and run each demo on the board.
- Run `laptop.py` against the real serial port.
- Record the board readings in `demo_tests/README.md`.
