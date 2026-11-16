#!/usr/bin/env python3
"""riscv-tests run REMOTELY: each core executes a test that lives in another tile.

    python3 benchmarks/run_remote_tests.py            # all suitable rv32ui tests
    python3 benchmarks/run_remote_tests.py add beq    # just these

In run_riscv_tests.py a test runs from its own tile, so the interconnect is
never used and both architectures give the same cycle count. Here core 0
runs code stored in tile 1, core 1 in tile 2 and core 2 in tile 0, all three
at once. Every instruction fetch and every load is a remote read, so real
processors load the fabric and the NoC and the bus can differ.

Each tile's image holds a three-instruction stub at the reset address, which
jumps to the next tile, and at offset 0x4000 the test that its neighbour
executes. A test reports through the status CSR of the core that runs it.
Tests that store to memory are left out: another tile may write only a
tile's mailbox, so their stores would be dropped. Needs the remote read
window off (the default). Writes results/remote_tests.md.
"""
import re
import struct
import sys
from pathlib import Path
from cooklib import HERE, BUILD, OB, MEM_WORDS, CC, OC, sh, build_sim, run

SUITE = HERE / "third_party" / "riscv-tests" / "isa"
STORES = {"sb", "sh", "sw", "st_ld", "ld_st", "ma_data", "fence_i"}   # write memory: not remote-safe
TEST_OFF = 0x4000                                                      # where a hosted test sits in its tile


def words(elf):
    binf = Path(elf).with_suffix(".bin")
    sh([OC, "-O", "binary", str(elf), str(binf)])
    d = binf.read_bytes()
    d += b"\0" * (-len(d) % 4)
    return [w for (w,) in struct.iter_unpack("<I", d)]


def images(test):
    """Three tile images: stub + the test the previous core executes from here."""
    mems = []
    for tile in range(3):
        host = (tile + 1) % 3                    # where this tile's core finds its test
        runner = (tile + 2) % 3                  # the core that executes the test stored here
        stub = BUILD / f"rem_stub_t{tile}.elf"
        src = BUILD / f"rem_stub_t{tile}.S"
        src.write_text(f".globl _start\n_start:\n    li t0, {(host << OB) + TEST_OFF:#x}\n    jr t0\n")
        sh([CC, "-march=rv32i", "-mabi=ilp32", "-nostdlib", "-nostartfiles", "-static",
            f"-Wl,-Ttext={(tile << OB) + 0x100:#x}", "-Wl,--build-id=none", "-o", str(stub), str(src)])
        telf = BUILD / f"rem_{test}_t{tile}.elf"
        sh([CC, "-march=rv32i", "-mabi=ilp32", "-nostdlib", "-nostartfiles", "-static",
            f"-DTILE_BASE={runner << OB:#x}", f"-I{HERE / 'env'}", f"-I{SUITE / 'macros' / 'scalar'}",
            f"-T{HERE / 'env' / 'link.ld'}", f"-Wl,--defsym,TEXT_BASE={(tile << OB) + TEST_OFF:#x}",
            "-Wl,--build-id=none", "-o", str(telf), str(SUITE / "rv32ui" / f"{test}.S")])
        s, t = words(stub), words(telf)
        img = [0] * MEM_WORDS
        img[64:64 + len(s)] = s
        img[TEST_OFF >> 2:(TEST_OFF >> 2) + len(t)] = t
        mem = BUILD / f"rem_{test}_t{tile}.mem"
        mem.write_text("".join(f"{w:08x}\n" for w in img))
        mems.append(str(mem))
    return mems


def local_cycles():
    """NoC cycle counts of the same tests run from their own tile, if that table exists."""
    f = HERE / "results" / "riscv_tests.md"
    if not f.exists():
        return {}
    return {m[1]: int(m[2]) for m in re.finditer(r"^\| (\w+) \| \d+ \| pass \| (\d+) \|", f.read_text(), re.M)}


def main():
    tests = sys.argv[1:] or sorted(p.stem for p in (SUITE / "rv32ui").glob("*.S") if p.stem not in STORES)
    sims = {a: build_sim(a, tag="remote") for a in ("noc", "bus")}
    local = local_cycles()
    rows, tot = [], {"noc": 0, "bus": 0, "local": 0}
    ok = {"noc": 0, "bus": 0}
    for test in tests:
        mems = images(test)
        r = {a: run(sims[a], mems, limit=1_500_000) for a in sims}
        for a in sims:
            ok[a] += r[a]["verdict"] == "pass"
        if all(r[a]["verdict"] == "pass" for a in sims):
            tot["noc"] += r["noc"]["cycles"]; tot["bus"] += r["bus"]["cycles"]; tot["local"] += local.get(test, 0)
        rows.append((test, local.get(test), r["noc"], r["bus"]))
        print(f"{test:8s} noc {r['noc']['verdict']:8s} {r['noc']['cycles']:8d}   bus {r['bus']['verdict']:8s} "
              f"{r['bus']['cycles']:8d}", flush=True)
    lines = ["# riscv-tests executed from another tile's memory", "",
             "Core 0 runs code stored in tile 1, core 1 in tile 2, core 2 in tile 0, all at once.",
             "Every instruction fetch is a remote read. Cycles until all three cores report.",
             "\"Local\" is the same test run from the core's own tile (`riscv_tests.md`).", "",
             "| Test | Local | NoC remote | NoC flits | Bus remote | Bus busy cycles | Bus / NoC |",
             "|---|---|---|---|---|---|---|"]
    for test, loc, n, b in rows:
        ratio = f"{b['cycles'] / n['cycles']:.2f}" if n["verdict"] == b["verdict"] == "pass" else "-"
        lines.append(f"| {test} | {loc or '-'} | {n['cycles'] if n['verdict'] == 'pass' else n['verdict']} | {n['flits']} | "
                     f"{b['cycles'] if b['verdict'] == 'pass' else b['verdict']} | {b['flits']} | {ratio} |")
    lines += ["", f"Passed: NoC {ok['noc']} of {len(rows)}, bus {ok['bus']} of {len(rows)}."]
    if tot["noc"]:
        lines.append(f"Total over the tests that pass on both: local {tot['local']}, NoC {tot['noc']}, bus {tot['bus']} "
                     f"cycles; bus / NoC = {tot['bus'] / tot['noc']:.2f}.")
    (HERE / "results" / "remote_tests.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[-2:]))


if __name__ == "__main__":
    main()
