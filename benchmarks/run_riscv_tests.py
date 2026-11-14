#!/usr/bin/env python3
"""Runs the riscv-tests ISA suite (rv32ui) on both architectures.

Every test is built three times, once per core tile (each tile's code lives
at its own address), and all three cores run it at the same time: on the NoC
(mesh_top, gateway on tile 3) and on the single-bus baseline (sb_top). The
result is read from each tile's status CSR; cycles are counted from the
moment the cores leave reset.

    python3 benchmarks/run_riscv_tests.py            # all of rv32ui
    python3 benchmarks/run_riscv_tests.py add lw     # just these

Needs benchmarks/third_party/riscv-tests (git clone --depth 1
https://github.com/riscv-software-src/riscv-tests.git), the RISC-V GCC
(riscv64-unknown-elf-gcc with the rv32i multilib) and Icarus Verilog.
Writes benchmarks/results/riscv_tests.md.

Tile memory is 4 KB by default, too small for some tests, so both systems
are compiled with NOC_OFFSET_BITS=16 (64 KB per tile) -- a knob override,
not a change to either design.
"""
import re
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
SUITE = HERE / "third_party" / "riscv-tests" / "isa"
BUILD = HERE / "build"
OB = 16                       # NOC_OFFSET_BITS for the benchmark build
MEM_WORDS = 1 << (OB - 2)
CC = "riscv64-unknown-elf-gcc"
OC = "riscv64-unknown-elf-objcopy"

RTL_SHARED = ["rtl/router/link_buffer.v", "rtl/network_interface/address_decoder.v",
              "rtl/network_interface/ni.v", "rtl/core/picorv32.v"]
RTL_NOC = ["rtl/router/noc_router.v", "rtl/router/end_buff.v", "rtl/router/bist_node.v",
           "rtl/integrated/mesh/noc_mesh.v", "rtl/integrated/mesh/mesh_top.v", "rtl/dma_ddr/gw_ni.v"]
RTL_BUS = ["single_bus/rtl/sb_bus.v", "single_bus/rtl/sb_mem_ni.v", "single_bus/rtl/sb_top.v",
           "single_bus/tb/axi4_mem_model.v"]


def sh(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


def build_image(test, tile):
    """Assemble one test for one tile; returns the .mem path."""
    base = tile << OB
    stem = BUILD / f"{test}_t{tile}"
    sh([CC, "-march=rv32i_zifencei", "-mabi=ilp32", "-nostdlib", "-nostartfiles", "-static",
        f"-DTILE_BASE={base:#x}", f"-I{HERE / 'env'}", f"-I{SUITE / 'macros' / 'scalar'}",
        f"-T{HERE / 'env' / 'link.ld'}", f"-Wl,--defsym,TEXT_BASE={base + 0x100:#x}",
        "-Wl,--build-id=none", "-o", f"{stem}.elf", str(SUITE / "rv32ui" / f"{test}.S")])
    sh([OC, "-O", "binary", f"{stem}.elf", f"{stem}.bin"])
    data = Path(f"{stem}.bin").read_bytes()
    data += b"\0" * (-len(data) % 4)
    prog = [w for (w,) in struct.iter_unpack("<I", data)]
    if len(prog) > MEM_WORDS - 64:
        raise SystemExit(f"{test}: {len(prog)} words do not fit in a tile")
    img = [0] * 64 + prog + [0] * (MEM_WORDS - 64 - len(prog))
    Path(f"{stem}.mem").write_text("".join(f"{w:08x}\n" for w in img))
    return f"{stem}.mem", len(prog)


def build_sim(arch):
    out = BUILD / f"bench_{arch}.out"
    files = ["benchmarks/tb/tb_bench.v"] + RTL_SHARED + (RTL_BUS if arch == "bus" else RTL_NOC)
    sh(["iverilog", "-g2012", "-Irtl/include", f"-DNOC_OFFSET_BITS={OB}"]
       + (["-DBENCH_BUS"] if arch == "bus" else []) + ["-s", "tb_bench", "-o", str(out)] + files,
       cwd=REPO)
    return out


def run(sim, images):
    r = sh(["vvp", "-n", str(sim)] + [f"+img{t}={m}" for t, m in enumerate(images)]
           + ["+limit=400000"])
    m = re.search(r"BENCH cycles=(\d+) st0=(\w+) st1=(\w+) st2=(\w+) trap=(\d+) bus=(\d+)", r.stdout)
    if not m:
        raise SystemExit("no BENCH line:\n" + r.stdout)
    cycles, st, trap, act = int(m[1]), [m[2], m[3], m[4]], m[5], int(m[6])
    if trap != "000":
        verdict = "TRAP"
    elif all(s.startswith("600d") for s in st):
        verdict = "pass"
    elif any(s.startswith("fa11") for s in st):
        verdict = "FAIL case " + ",".join(str(int(s[4:], 16)) for s in st if s.startswith("fa11"))
    else:
        verdict = "TIMEOUT"
    return cycles, verdict, act


def main():
    BUILD.mkdir(exist_ok=True)
    (HERE / "results").mkdir(exist_ok=True)
    tests = sys.argv[1:] or sorted(p.stem for p in (SUITE / "rv32ui").glob("*.S"))
    sims = {a: build_sim(a) for a in ("noc", "bus")}
    rows, npass = [], {"noc": 0, "bus": 0}
    for test in tests:
        built = [build_image(test, t) for t in range(3)]
        images = [b[0] for b in built]
        res = {a: run(sims[a], images) for a in sims}
        for a in sims:
            npass[a] += res[a][1] == "pass"
        rows.append((test, built[0][1], res["noc"], res["bus"]))
        print(f"{test:10s} noc {res['noc'][1]:8s} {res['noc'][0]:7d}   bus {res['bus'][1]:8s} {res['bus'][0]:7d}")

    lines = ["# riscv-tests rv32ui on both architectures", "",
             "Three cores run each test at the same time, from their own tile memory.",
             f"Tile memory {1 << OB >> 10} KB (`NOC_OFFSET_BITS={OB}`). Cycles from core reset release",
             "until all three cores report. Interconnect flits: flits entering the mesh, or",
             "bus-busy cycles.", "",
             "| Test | Words | NoC | NoC cycles | NoC flits | Bus | Bus cycles | Bus busy |",
             "|---|---|---|---|---|---|---|---|"]
    for test, words, n, b in rows:
        lines.append(f"| {test} | {words} | {n[1]} | {n[0]} | {n[2]} | {b[1]} | {b[0]} | {b[2]} |")
    lines += ["", f"Passed: NoC {npass['noc']} of {len(rows)}, bus {npass['bus']} of {len(rows)}."]
    (HERE / "results" / "riscv_tests.md").write_text("\n".join(lines) + "\n")
    print(lines[-1])


if __name__ == "__main__":
    main()
