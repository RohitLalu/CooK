# Demo tests

> **Status: OPEN** (2026-11-16). All demos are written and pass in simulation (`results.md`, written by the runner, is complete). Open, and only closable in Vivado and on the board: no 64 KB-tile bitstream has been built and no demo has run there.

Programs and one optional hardware piece for showing the system working on
the board. Everything here runs on 64 KB tiles (`NOC_OFFSET_BITS=16`) and is
checked in simulation first. **None of it has run on the board yet**, and a
64 KB-tile bitstream has not been built in Vivado.

## The demos

| # | Demo | Files | What you see on the board | Simulated |
|---|---|---|---|---|
| 1 | **Crypto on three cores, with and without a fault** | `encryption_code/crypto/`, `encryption_code/run_crypto.py --board` | Three pass LEDs; display ends in `2806`, the first ciphertext bytes. Set a fault switch and press reset: same result on the NoC. On the single-bus build with its fault switch: all cores fail | yes, both architectures |
| 2 | **Traffic that never stops** | `programs/loop_traffic.c` | Display counts up. Flip a fault switch **without** reset: the cores that use that link turn their fail LEDs on, the others keep counting | yes |
| 3 | **Parallel speed-up** | `programs/speedup.c` | Core 0 does the work alone, then shares it with cores 1 and 2; time the two phases (status `5255000A`, then `5255000B`, then pass) | yes |
| 4 | **DMA to DDR and back** | `programs/dma_lock.c` | LED17 blue flickers (DMA interrupts), status counts rounds | yes, with the DMA model |
| 5 | **Lock contention** | the same program on all three cores | All three cores keep making rounds: the gateway hands the one DMA lock round in turn | yes |
| 6 | **Dhrystone on three cores** | `benchmarks/run_c_benchmarks.py` (images `benchmarks/build/dhry500_t0.mem` to `_t2.mem`) | Three pass LEDs after about 40 ms | yes, both architectures |
| 8 | **Restart a stopped core** | `programs/restart.c` | Core 1 stops on purpose (its error LED and code 1 show briefly), core 0 notices and restarts it, both end on pass | yes |
| 7 | **Laptop link** (live demo) | `encryption_code/link/`, `encryption_code/rtl/` | Type a message on the laptop; the board decrypts it and shows the first 8 characters, or encrypts it and the laptop checks the answer | yes |

```
python3 demo_tests/run_demos.py            # simulate 2 to 5 and 8, writes results.md
python3 demo_tests/run_demos.py --board    # build their board images
python3 encryption_code/run_link_sim.py    # simulate 7
python3 encryption_code/run_link_sim.py --board # build its board images
```

The demos are simulated with the remote read window on (`RD_PROTECT = 1` on
`mesh_top`): a tile's memory outside its mailbox cannot be read by other
tiles. Set the same generic on the board build for the crypto and link demos,
so that "core 1's keys stay in core 1" is enforced by hardware. Leave it off
for `alltoall.S`, which fetches code from other tiles.

Board images land in `benchmarks/build/` as `<name>_t00.mem` to `_t02.mem`.
To use a set, build the FPGA with the Verilog define `NOC_OFFSET_BITS=16` and
point the three tile memory images at it (`MEM_PREFIX` of `nexys4ddr_top`).

## The laptop link

Optional hardware with its own board top. The normal top, `nexys4ddr_top`,
contains none of it, and the rest of the system is unchanged.

- `encryption_code/rtl/uart_port.v` sits on core 0's memory bus in front of its network
  interface. It answers one page of addresses (`0xFFFFF000`) and passes every
  other access through untouched. 115200 baud, 8N1, on the board's USB serial
  port (the same cable used for programming).
- `encryption_code/rtl/seven_seg_text.v` shows 8 characters on the display while core 0 has
  text to show.
- `encryption_code/link/core0_link.c` is core 0's program. It holds the key but has no AES
  code: each message goes across the NoC to core 1 as a job.
- `encryption_code/link/laptop.py` is the laptop's side (`pip install pyserial`).

To build it: make `encryption_code/rtl/nexys4ddr_live_top.v` the synthesis
top, add the three files in `encryption_code/rtl/` to the Vivado project,
define `NOC_OFFSET_BITS=16`, and use the images from
`run_link_sim.py --board`. The normal top, `nexys4ddr_top`, stays as it is
for everything else. Then:

```
python3 encryption_code/link/laptop.py --port COM5 show "HELLO NOC"
python3 encryption_code/link/laptop.py --port COM5 encrypt "any message up to 64 characters"
```

**Why this shows the FPGA did the work**
- `show` sends ciphertext only. The plaintext appears on the board's own
  display, so it was decrypted there.
- Core 0 has no AES code, so the answer crossed the NoC to core 1 and back.
- `encrypt` returns ciphertext that the laptop's own AES decrypts to the
  message you typed.
- Set a fault switch and press reset: it still works. The single-bus build
  with its fault switch does not.

**Limits to state when presenting**
- The key is compiled into both sides. This is not a key exchange.
- AES-128 in ECB mode on whole blocks, messages padded with spaces. Fine for a
  demonstration, not how AES should be used for real data.
- A 7-segment digit cannot draw every letter well (K, M, V, W, X are rough).
