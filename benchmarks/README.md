# Benchmarks

Programs run on both architectures: the NoC (`rtl/`) and the single-bus
baseline (`single_bus/`). One testbench, `tb/tb_bench.v`, builds either
system; the runners build the programs, run them on both and write a table
to `results/`.

Both systems are compiled with `NOC_OFFSET_BITS=16` (64 KB per tile) for
everything here: 4 KB is too small for these programs. That is a compile-time
knob, not a design change. Simulation is Icarus Verilog, roughly 1,500 clock
cycles per second with three cores, so the longer runs take minutes to an hour.

## Install before running

| Tool | Needed for | How |
|---|---|---|
| RISC-V GCC with the `rv32i/ilp32` multilib | everything | `riscv64-unknown-elf-gcc` from Homebrew's `riscv-gnu-toolchain` (built from riscv-collab/riscv-gnu-toolchain) |
| Icarus Verilog | everything | `brew install icarus-verilog` |
| **Spike** (reference simulator) and `dtc` | `run_arch_test.py` | `sh benchmarks/tools/install_spike.sh` builds both from source into `third_party/tools/` (about ten minutes, nothing system-wide) |
| Test suites | each runner | clone into `benchmarks/third_party/` (not committed), commands below |

```
cd benchmarks/third_party
git clone --depth 1 https://github.com/riscv-software-src/riscv-tests.git
git clone --depth 1 --branch 3.9.1 https://github.com/riscv-non-isa/riscv-arch-test.git
git clone --depth 1 https://github.com/eembc/coremark.git
```

## What there is

| Runner | Suite | Result file |
|---|---|---|
| `run_riscv_tests.py` | riscv-tests `rv32ui` (42 tests), three cores at once | `results/riscv_tests.md` |
| `run_arch_test.py` | riscv-arch-test 3.9.1, RV32I base set (39 tests), signatures compared with Spike | `results/arch_test.md` |
| `run_c_benchmarks.py` | Dhrystone 2.1 (from riscv-tests) and CoreMark | `results/c_benchmarks.md` |
| `run_crypto.py` | three-core crypto demo: keys and arbiter, AES-128, WOTS signature; healthy and with one fault | `results/crypto.md` |

Run any of them from the repo root, for example `python3 benchmarks/run_arch_test.py`.

## How the suites were fitted to CooK

- **No console, no timer, no CSRs on a tile.** A program reports through the
  tile's status CSR (`0x600D....` pass, `0xFA11....` fail), and the testbench
  counts clock cycles. `env/riscv_test.h` does this for riscv-tests,
  `arch_test/cook/model_test.h` for riscv-arch-test.
- **riscv-arch-test** uses release 3.9.1, the last with plain signature tests
  (newer releases need the ACT4 framework: Ruby, UDB, Sail). Each test runs on
  Spike for the reference signature, then on tile 0 of each architecture; the
  testbench dumps the signature region and the three must match. Built with
  `-mno-relax`, otherwise the linker pads with compressed nops that an RV32I
  core cannot execute.
- **C runtime**: `crt/crt0.S` (start-up), `crt/tile.ld` (linker script),
  `crt/tile.h` (CSRs, mailbox), `crt/libmin.c` (memcpy and friends). Layout of
  a tile: reset stub at `0x100`, mailbox `0x800`–`0xEFF` kept free (the only
  region other tiles may write), program from `0x1000`, stack at the top.
  `main`'s return value becomes the status word.
- **Dhrystone** is the suite's source unchanged; `dhrystone/dhry_cook.c`
  checks the final values the benchmark lists. The suite fixes 500 runs.
- **CoreMark** is unchanged with `coremark/core_portme.c`; pass means its own
  "Correct operation validated" check. One core only, one and two iterations,
  because an iteration is millions of cycles.
- RV32I only: multiply and divide are libgcc routines. The cores also have no
  barrel shifter, so shifts cost a cycle per few bits.

## What the results mean

All of these programs run inside one tile, so they give the same cycle counts
on the NoC and on the bus. They show that the cores, memory and runtime work
inside each system. They do not compare the interconnects; the comparison is
in the fault tests (`make m3`, `single_bus`'s `make faults`) and in programs
that communicate (`alltoall`, the crypto demo).

Final numbers and the two tests that cannot pass: `results/SUMMARY.md`.
- riscv-tests `ma_data` traps (PicoRV32 traps on misaligned access).
- arch-test `jal-01` is larger than the largest possible tile (1 MB). Six
  branch tests need more than 64 KB; the runner retries those with 1 MB tiles.
- `fence_i` passes because `rtl/core/picorv32.v` now accepts `fence.i` as a
  no-op.

## Not done

- A mode that runs a test from another tile's memory, so that every fetch
  crosses the interconnect. It needs the remote write window widened.
- core-v-verif's own test programs: only Dhrystone and CoreMark were taken.
