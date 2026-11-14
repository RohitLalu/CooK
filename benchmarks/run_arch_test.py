#!/usr/bin/env python3
"""riscv-arch-test (RV32I base set) on both architectures, checked against Spike.

For every test:
  1. build it for Spike and run it there: Spike writes the reference signature
  2. build it for a CooK tile and run it on the NoC and on the single bus:
     the testbench dumps the same signature region from tile 0's memory
  3. the three signatures must be identical

    sh benchmarks/tools/install_spike.sh                 # once: builds Spike
    git clone --depth 1 --branch 3.9.1 \\
        https://github.com/riscv-non-isa/riscv-arch-test.git benchmarks/third_party/riscv-arch-test
    python3 benchmarks/run_arch_test.py                  # all 39 tests
    python3 benchmarks/run_arch_test.py add-01 lw-align-01

Release 3.9.1 is the last one with plain signature tests; later releases need
the ACT4 framework (Ruby, UDB, Sail). Writes results/arch_test.md.
The tests stay inside one tile, so core 0 runs them and the other cores idle.
"""
import os
import subprocess
import sys
from cooklib import HERE, BUILD, OB, CC, sh, to_mem, build_sim, run

SUITE = HERE / "third_party" / "riscv-arch-test" / "riscv-test-suite"
SRC = SUITE / "rv32i_m" / "I" / "src"
SPIKE = HERE / "third_party" / "tools" / "bin"
AT = HERE / "arch_test"
# -mno-relax: with relaxation the linker pads the tests' alignment with
# compressed nops, which an RV32I core cannot execute
COMMON = ["-march=rv32i", "-mabi=ilp32", "-mno-relax", "-static", "-mcmodel=medany", "-nostdlib",
          "-nostartfiles", "-DXLEN=32", "-DTEST_CASE_1=True", f"-I{SUITE / 'env'}", "-Wl,--build-id=none"]


def symbols(elf):
    out = sh(["riscv64-unknown-elf-nm", str(elf)]).stdout
    return {l.split()[2]: int(l.split()[0], 16) for l in out.splitlines() if len(l.split()) == 3}


def reference(test):
    """Signature from Spike, as a list of 8-digit hex words; None if Spike does not finish."""
    elf, sig = BUILD / f"at_{test}_spike.elf", BUILD / f"at_{test}.ref"
    sh([CC, *COMMON, f"-I{AT / 'spike'}", f"-T{AT / 'spike' / 'link.ld'}", "-o", str(elf),
        str(SRC / f"{test}.S")])
    env = dict(os.environ, PATH=f"{SPIKE}:{os.environ['PATH']}")
    try:
        subprocess.run(["spike", "--isa=rv32i", f"+signature={sig}", "+signature-granularity=4", str(elf)],
                       env=env, timeout=60, check=True, capture_output=True)
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
        return None
    return sig.read_text().split()


BIG_OB = 20      # 1 MB tiles (the largest a packet can address) for the tests that do not fit in 64 KB
_big_sims = {}


def big_sims():
    if not _big_sims:
        _big_sims.update({a: build_sim(a, tag="archbig", ob=BIG_OB) for a in ("noc", "bus")})
    return _big_sims


def on_cook(test, sims, ob=OB):
    """Signatures from tile 0 on each architecture: {arch: (words or None, cycles, verdict)}."""
    elf = BUILD / f"at_{test}_cook.elf"
    sh([CC, *COMMON, "-DTILE_BASE=0", f"-I{AT / 'cook'}", f"-T{AT / 'cook' / 'link.ld'}",
        "-Wl,--defsym,TEXT_BASE=0x100", "-o", str(elf), str(SRC / f"{test}.S")])
    mem = BUILD / f"at_{test}_cook.mem"
    to_mem(elf, mem, ob)
    sym = symbols(elf)
    lo, hi = sym["begin_signature"] >> 2, sym["end_signature"] >> 2
    res = {}
    for arch, sim in sims.items():
        sig = BUILD / f"at_{test}_{arch}.sig"
        r = run(sim, [str(mem), None, None], limit=6_000_000,
                extra=[f"+sig={sig}", f"+sig_lo={lo}", f"+sig_hi={hi}"])
        res[arch] = (sig.read_text().split() if r["verdict"] == "pass" else None, r["cycles"], r["verdict"])
    return res


def main():
    if not (SPIKE / "spike").exists():
        raise SystemExit("Spike is not built: run  sh benchmarks/tools/install_spike.sh  first")
    tests = sys.argv[1:] or sorted(p.stem for p in SRC.glob("*.S"))
    sims = {a: build_sim(a, tag="arch") for a in ("noc", "bus")}
    lines = ["# riscv-arch-test, RV32I base set, both architectures against Spike", "",
             f"Release 3.9.1, tile memory {1 << OB >> 10} KB ({1 << BIG_OB >> 10} KB for the tests that need it). Reference signatures from Spike",
             "(`--isa=rv32i`). A test passes when the signature read from the tile equals Spike's.", "",
             "| Test | Tile KB | Signature words | NoC | NoC cycles | Bus | Bus cycles |",
             "|---|---|---|---|---|---|---|"]
    npass = {"noc": 0, "bus": 0}
    for test in tests:
        tile_kb = 1 << OB >> 10
        try:
            ref = reference(test)
            try:
                got = on_cook(test, sims)
            except SystemExit as e:
                if "do not fit" not in str(e):
                    raise
                got = on_cook(test, big_sims(), BIG_OB)   # same systems, larger tiles
                tile_kb = 1 << BIG_OB >> 10
        except SystemExit as e:                       # does not build, or too big for any tile
            reason = "larger than the biggest tile (1 MB)" if "do not fit" in str(e) else "build error"
            print(f"{test:20s} skipped: {reason}", flush=True)
            lines.append(f"| {test} | - | - | skipped: {reason} | - | skipped | - |")
            continue
        row = []
        for arch in ("noc", "bus"):
            words, cycles, verdict = got[arch]
            if ref is None:
                v = "no reference (Spike did not finish)"
            elif words is None:
                v = verdict
            elif words == ref:
                v = "pass"
                npass[arch] += 1
            else:
                bad = sum(a != b for a, b in zip(words, ref)) + abs(len(words) - len(ref))
                v = f"MISMATCH ({bad} words)"
            row += [v, cycles]
        print(f"{test:20s} noc {row[0]:22s} bus {row[2]}", flush=True)
        lines.append(f"| {test} | {tile_kb} | {len(ref) if ref else '-'} | {row[0]} | {row[1]} | {row[2]} | {row[3]} |")
    lines += ["", f"Passed: NoC {npass['noc']} of {len(tests)}, bus {npass['bus']} of {len(tests)}."]
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "arch_test.md").write_text("\n".join(lines) + "\n")
    print(lines[-1])


if __name__ == "__main__":
    main()
