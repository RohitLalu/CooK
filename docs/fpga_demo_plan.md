# FPGA demos: what is ready, what is planned

Goal: show on the board that the computation happens in the FPGA's NoC, on
three cores at once, and not on the laptop.

## 1. Three-core crypto demo (passes in simulation on both architectures, not yet on the board)

Code: `benchmarks/crypto/`. All C, RV32I only: no multiplier, no FPU, no
custom instructions, no extra hardware.

| Core | Job | What stays private to its tile |
|---|---|---|
| 0 | Key generator and arbiter: derives the AES key and the signing seed (SHA-256), hands out jobs, checks results | the nonce, the verification state |
| 1 | AES-128: encrypts, then decrypts on request | round keys, S-boxes, block state |
| 2 | Digital signature: one-time key pair, sign | secret chain values, hash state |

Shared data goes only through the mailboxes (offsets `0x800`–`0xEFF` of each
tile, the one region other tiles may write). A job carries the key and the
input; a result carries the output. Protocol: `crypto/proto.h`.

**Signature scheme: WOTS over SHA-256, not ML-DSA.** ML-DSA-44 does not fit
this system as it stands: it needs tens of kilobytes of working memory on top
of its code, and its polynomial arithmetic is all multiplication, which these
cores do in software. A hash-based signature needs only SHA-256. WOTS is a
one-time signature: one key pair signs one message. If ML-DSA matters for the
write-up, it needs larger tiles and the core's multiplier enabled, which is a
hardware change to decide separately.

**AES-128 only.** AES-256 is the same code with a longer key schedule; not
written.

In simulation it passes on the NoC and on the bus, the ciphertext matches
OpenSSL, and with the arbiter-to-AES link dead the NoC still finishes while a
stuck bus arbiter fails at once (`benchmarks/results/SUMMARY.md`).

To put it on the board:
1. Build the images: `python3 benchmarks/run_crypto.py --board` (writes
   `benchmarks/build/crypto_board_t00..02.mem`, 64 KB images).
2. Build the FPGA with 64 KB tiles: add the Verilog define
   `NOC_OFFSET_BITS=16` to the Vivado project and point the memory images at
   those three files. Not done or tried yet.
3. Expected: LED4–LED6 on (three cores pass), and the display's last four
   digits show the first two ciphertext bytes, which core 0 can only have got
   from core 1.

## 2. Laptop link (planned, not built)

What you asked for: type a message on the laptop, send it encrypted, core 1
decrypts and the display shows the first characters; or the reverse.

It needs one new hardware piece: a UART on the board's USB serial port
(pins C4 and D4, the same cable used for programming).

| Piece | What it is | Size of the job |
|---|---|---|
| UART receiver and transmitter | small RTL block, 115200 baud | new module + testbench |
| Where it attaches | registers in core 0's tile (new CSRs for "byte ready", "read byte", "send byte") | a change to `ni.v`, or a small wrapper beside it |
| Core 0 program | reads the message from the UART, forwards it as a job, sends the result back | extends `core0_arbiter.c` |
| Laptop script | Python with `pyserial` and an AES library: encrypts, sends, prints what comes back | new script |
| Display text | six characters on the 7-segment display | a character table in `seven_seg.v`, or hex only |

Decision needed before building: attaching the UART touches the NI, which
both architectures share. The alternative is a UART that sits beside core 0's
memory bus without touching `ni.v`.

**How this proves the FPGA did the work:**
- The laptop sends ciphertext and never sends the key or the plaintext in
  that direction; the plaintext then appears on the board's own display.
- Core 0 has no AES code, so the answer must have crossed the NoC to core 1.
- Break a link with the fault switches and press reset: the demo still works
  (the routers go around it). On the single-bus build, one fault stops it.
- Unplug the USB data after sending: the board still shows the result.

## 3. Other demos worth showing

| Demo | What it shows | Needs |
|---|---|---|
| **Fault switch during the crypto demo** | the same computation survives any single link fault on the NoC and dies on the bus | section 1 on the board, both bitstreams |
| **Looping all-to-all with a live counter** | traffic never stops; flipping a fault switch without reset shows timeouts live (the test the current program cannot show) | a looping variant of `alltoall.S` |
| **Parallel speed-up** | hash N blocks on one core, then split across three: display the time for each | a cycle counter CSR, small C program |
| **DMA to DDR and back** | a core claims the lock, moves a block to DDR and back, compares | C program using the gateway registers; already covered in simulation |
| **Lock contention** | three cores fight for the DMA lock; display shows whose turn it is | small C program |
| **Dhrystone on three cores** | each core's pass LED; same score on NoC and bus | images exist (`run_c_benchmarks.py`) |
