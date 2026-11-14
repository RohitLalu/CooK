# Benchmarks

Programs run on both architectures: the NoC (`rtl/`) and the single-bus
baseline (`single_bus/`). One testbench, `tb/tb_bench.v`, builds either
system and prints the cycle count and each core's result.

## riscv-tests (rv32ui)

```
git clone --depth 1 https://github.com/riscv-software-src/riscv-tests.git benchmarks/third_party/riscv-tests
python3 benchmarks/run_riscv_tests.py          # writes results/riscv_tests.md
```

- `env/riscv_test.h` replaces the suite's environment: a test reports pass or
  fail through the tile's status CSR, like every CooK program.
- Each test is built once per core tile and all three cores run it together.
- Both systems are compiled with `NOC_OFFSET_BITS=16` (64 KB per tile),
  because 4 KB is too small for some tests. This is a compile-time knob, not a
  design change.

Result: 40 of 42 pass on both. `fence_i` and `ma_data` trap on both, because
PicoRV32 does not implement `fence.i` and traps on misaligned access.

These tests never leave the tile, so the cycle counts are equal on both
systems (one cycle apart, a testbench start offset). They show the cores work
inside each system; they do not compare the interconnects.

## Toolchain

`riscv64-unknown-elf-gcc` from Homebrew's `riscv-gnu-toolchain` (built from
riscv-collab/riscv-gnu-toolchain), with the `rv32i/ilp32` multilib.
