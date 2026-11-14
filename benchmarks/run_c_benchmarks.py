#!/usr/bin/env python3
"""Dhrystone and CoreMark on both architectures, three cores at once.

    python3 benchmarks/run_c_benchmarks.py [dhrystone] [coremark]

Sources come from benchmarks/third_party (riscv-tests for Dhrystone,
eembc/coremark for CoreMark), unmodified; the ports are dhrystone/ and
coremark/ here, the runtime is crt/. Writes results/c_benchmarks.md.

No timer exists on a tile, so the testbench counts clock cycles.
RV32I only: multiply and divide are libgcc routines.
"""
import sys
from cooklib import HERE, CLK_HZ, build_c, build_sim, run

TP = HERE / "third_party"
DHRY = TP / "riscv-tests" / "benchmarks" / "dhrystone"
CM = TP / "coremark"


def dhrystone(runs, tile):
    return build_c(f"dhry{runs}", [DHRY / "dhrystone.c", DHRY / "dhrystone_main.c",
                                   HERE / "dhrystone" / "dhry_cook.c"], tile,
                   flags=[f"-I{HERE / 'dhrystone'}", f"-I{DHRY}", "-Dmain=dhry_main",
                          f"-DNUMBER_OF_RUNS={runs}", "-w", "-fno-inline", "-std=gnu89",
                          "-Wl,--undefined=main"])


def coremark(iters, tile):
    return build_c(f"cm{iters}", [CM / f for f in ("core_list_join.c", "core_main.c", "core_matrix.c",
                                                    "core_state.c", "core_util.c")]
                   + [HERE / "coremark" / "core_portme.c"], tile,
                   flags=[f"-I{CM}", f"-I{CM / 'barebones'}", "-Dmain=coremark_main",
                          f"-DITERATIONS={iters}", "-DHAS_FLOAT=0", "-DHAS_TIME_H=0",
                          "-DMAIN_HAS_NOARGC=1", "-include", "stddef.h", "-DCLOCKS_PER_SEC=1", '-DFLAGS_STR="-O2 rv32i"',
                          "-w", "-Wl,--undefined=main"])


# name: (builder, iteration counts, cores that run it, cycle limit, unit, divisor, derived name)
# Dhrystone: the suite fixes 500 runs, so one run and cycles / 500 (start-up
# included, about 2 %). CoreMark: 1 and 2 iterations, difference taken; one
# core only, because an iteration is millions of cycles and Icarus is slow.
BENCH = {
    "dhrystone": (dhrystone, (500,), 3, 2_500_000, "Dhrystones/s", 1757.0, "DMIPS"),
    "coremark":  (coremark, (1, 2), 1, 80_000_000, "CoreMark (iterations/s)", CLK_HZ / 1e6, "CoreMark/MHz"),
}


def main():
    names = sys.argv[1:] or list(BENCH)
    sims = {a: build_sim(a) for a in ("noc", "bus")}
    lines = ["# Dhrystone and CoreMark on both architectures", "",
             "Each core runs the benchmark from its own tile memory (64 KB tiles, RV32I, `-O2`,",
             f"multiply and divide in software). Rates assume the board's {CLK_HZ // 1_000_000} MHz clock.", "",
             "| Benchmark | Arch | Cores | Result | Bytes | Cycles per iteration | Rate | Derived |",
             "|---|---|---|---|---|---|---|---|"]
    for name in names:
        builder, counts, cores, limit, unit, div, dname = BENCH[name]
        for arch, sim in sims.items():
            res = {}
            for n in counts:
                built = [builder(n, t) if t < cores else (None, 0) for t in range(3)]
                res[n] = run(sim, [b[0] for b in built], limit=limit)
                size = built[0][1]
            ok = all(r["verdict"] == "pass" for r in res.values())
            lo, hi = counts[0], counts[-1]
            per = res[hi]["cycles"] / hi if lo == hi else (res[hi]["cycles"] - res[lo]["cycles"]) / (hi - lo)
            rate = CLK_HZ / per
            verdict = "pass" if ok else res[hi]["verdict"]
            print(f"{name:10s} {arch}  {verdict:8s} {per:12.0f} cycles/iter  {rate:9.2f} {unit}  "
                  f"{rate / div:.3f} {dname}", flush=True)
            lines.append(f"| {name} | {arch} | {cores} | {verdict} | {size} | {per:.0f} | "
                         f"{rate:.2f} {unit} | {rate / div:.3f} {dname} |")
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "c_benchmarks.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
