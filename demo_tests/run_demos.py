#!/usr/bin/env python3
"""Simulates the board demos in demo_tests/programs on the NoC and checks them.

    python3 demo_tests/run_demos.py                 # all
    python3 demo_tests/run_demos.py traffic dma     # some: traffic, dma, speedup, restart, fixes
                                                    # (fixes: the program faults found on the board)
    python3 demo_tests/run_demos.py --board         # only build the board images

Board images: benchmarks/build/demo_<name>_tNN.mem (64 KB tiles).
Writes demo_tests/results.md.
"""
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "benchmarks"))
from cooklib import BUILD, OB, REPO, RTL, RTL_SHARED, build_c, sh   # noqa: E402

P = HERE / "programs"
C = HERE.parent / "encryption_code" / "crypto"        # sha256 for the speed-up demo


def images(name, flags=(), worker_flags=None):
    """One image per core tile; cores 1 and 2 get worker_flags when given."""
    src = [P / f"{name}.c"] + ([C / "sha256.c"] if name == "speedup" else [])
    out = []
    for t in range(3):
        f = list(flags) + (list(worker_flags) if worker_flags and t else []) + [f"-I{C}"]
        tag = "w" if worker_flags and t else ""
        out.append(build_c(f"demo_{name}{tag}{'_'.join(x.strip('-D') for x in flags)}", src, t, flags=f)[0])
    return out


def sim():
    out = BUILD / "demo.out"
    sh(["iverilog", "-g2012", "-Irtl/include", f"-DNOC_OFFSET_BITS={OB}", "-s", "tb_demo", "-o", str(out),
        "demo_tests/tb/tb_demo.v", "tb/axi_dma_model.v", *RTL_SHARED, *RTL["noc"]], cwd=REPO)
    return out


def run(out, imgs, **args):
    text = sh(["vvp", "-n", str(out), *[f"+img{t}={m}" for t, m in enumerate(imgs)],
               *[f"+{k}={v}" for k, v in args.items()]]).stdout
    m = re.search(r"DEMO cycles=(\d+) st0=(\w+) st1=(\w+) st2=(\w+) trap=(\d+) err=(\w+) gw=(\d+)", text)
    if not m:
        raise SystemExit("no DEMO line:\n" + text)
    st = [(int(a), int(b), c) for a, b, c in re.findall(r"ST (\d) (\d+) (\w+)", text)]
    return dict(cycles=int(m[1]), status=[m[2], m[3], m[4]], trap=m[5], err=m[6], gw=m[7], changes=st)


def traffic(out):
    """Healthy: every core keeps passing. Then a link dies mid-run: the cores using it fail."""
    imgs = images("loop_traffic")
    ok = run(out, imgs, limit=40000)
    bad = run(out, imgs, limit=60000, fault="0004", fault_at=20000)     # link tile 0 -> east, after BIST
    good = all(s.startswith("600d") for s in ok["status"]) and ok["trap"] == "000"
    seen = any(s.startswith("fa11") for s in bad["status"])
    rows = [("Looping traffic, healthy, 40,000 cycles", good,
             "passes so far: " + ", ".join(str(int(s[4:], 16)) for s in ok["status"])),
            ("Looping traffic, link 0→1 goes silent at cycle 20,000 (no reset)", seen,
             "status " + ", ".join(bad["status"]) + f"; NI flags {bad['err']}")]
    return rows


def dma(out):
    """Three cores, three rounds each, taking turns on the DMA lock."""
    r = run(out, images("dma_lock", ["-DROUNDS=3"]), limit=400000, need=7)
    good = all(s == "600d0003" for s in r["status"]) and r["trap"] == "000" and r["gw"] == "000"
    return [("DMA to DDR and back with the lock, 3 cores × 3 rounds", good,
             f"status {', '.join(r['status'])}; {r['cycles']} cycles; gateway flags {r['gw']}")]


def speedup(out):
    """Phase A on one core against phase B on three: time between core 0's status marks."""
    blocks = 6
    r = run(out, images("speedup", [f"-DBLOCKS={blocks}"], ["-DWORKER"]), limit=3000000, need=1)
    at = {v: c for core, c, v in r["changes"] if core == 0}
    good = r["status"][0] == f"600d{blocks:04x}" and r["trap"] == "000"
    if not good or "5255000b" not in at:
        return [("Parallel speed-up", False, f"status {r['status']}")]
    a = at["5255000b"] - at["5255000a"]
    b = at[r["status"][0]] - at["5255000b"]
    return [(f"Parallel speed-up, 3 × {blocks} chained SHA-256 blocks", good,
             f"one core {a} cycles, three cores {b} cycles: {a / b:.2f}× faster; digests equal")]


def restart(out):
    """Core 1 traps; core 0 sees it through the core-control CSR and restarts it."""
    v = build_c("demo_restart_victim", [P / "restart.c"], 1, flags=["-DVICTIM"])[0]
    imgs = [build_c("demo_restart", [P / "restart.c"], 0)[0], v, build_c("demo_restart", [P / "restart.c"], 2)[0]]
    r = run(out, imgs, limit=400000, need=1)
    trapped = any(core == 1 and val == "52550001" for core, _, val in r["changes"])
    good = r["status"][0] == "600d0001" and r["status"][1] == "600d0002" and trapped and r["trap"][1] == "0"
    return [("Restart: core 1 traps, core 0 restarts it", good,
             f"status {', '.join(r['status'])}; core 1 running again (trap bits {r['trap']}); {r['cycles']} cycles")]


# ---- the program faults found on the board (todo/sw_changes.md), as regressions ----
# Fault masks are the board's multi-link codes (nexys4ddr_top.v fault_pattern):
HORIZONTAL, ALL_LINKS = "8484", "95A6"     # SW 1003, SW 100B


def board_fixes(out):
    rows = []
    rv = [build_c("demo_restart", [P / "restart.c"], 0)[0],
          build_c("demo_restart_victim", [P / "restart.c"], 1, flags=["-DVICTIM"])[0],
          build_c("demo_restart", [P / "restart.c"], 2)[0]]

    # 1. restart, core 1 cut off: must report "unreachable" (3) at once, not "no pass" (2) after 200,000 polls
    for what, args in (("links 0-1 and 2-3 dead", dict(fault=HORIZONTAL)), ("router 1 broken", dict(frt="2"))):
        r = run(out, rv, limit=400000, need=1, **args)
        rows.append((f"Fix 1, restart with core 1 cut off ({what})", r["status"][0] == "fa110003",
                     f"core 0 {r['status'][0]} after {r['cycles']} cycles (board, before the fix: fa110002 after 12.2 s)"))

    # 2b. restart after CPU_RESET: the second run must trap and restart again, not pass at once
    r = run(out, rv, limit=400000, need=1, rerun=1)
    rows.append(("Fix 2b, restart after CPU_RESET (memory not reloaded)",
                 r["status"][0] == "600d0001" and r["status"][1] == "600d0002",
                 f"second run: core 0 {r['status'][0]}, core 1 {r['status'][1]} (board, before: core 0 fa110001)"))

    # 1. DMA with the gateway unreachable: "lock never granted" (1), not "data differs" (4)
    dm = images("dma_lock", ["-DROUNDS=3"])
    r = run(out, dm, limit=400000, need=7, frt="8")
    rows.append(("Fix 1, DMA with the gateway's router broken", all(x == "fa110001" for x in r["status"]),
                 f"status {', '.join(r['status'])} (board, before: fa110004)"))
    r = run(out, dm, limit=400000, need=5, fault=HORIZONTAL)
    rows.append(("Fix 1, DMA with links 0-1 and 2-3 dead (cores 0, 2 cut off from the gateway)",
                 r["status"][0] == "fa110001" and r["status"][2] == "fa110001",
                 f"status {', '.join(r['status'])} (core 1 still reaches the gateway)"))

    # 2a. speed-up after CPU_RESET with every link dead: must fail (2), not reuse the first run's results
    sp = images("speedup", ["-DBLOCKS=2"], ["-DWORKER"])
    r = run(out, sp, limit=4000000, need=1, rerun=1, fault=ALL_LINKS)
    rows.append(("Fix 2a, speed-up after CPU_RESET with every link dead", r["status"][0] == "fa110002",
                 f"core 0 {r['status'][0]} (board, before: a false pass, 600d07d0)"))
    return rows


def dma_rate(out):
    """DMA rate, both directions, from the times core 0 changes phase (simulation, DMA model)."""
    words, ra, rb = 448, 4, 2
    r = run(out, images("dma_rate", [f"-DWORDS={words}", f"-DROUNDS_A={ra}", f"-DROUNDS_B={rb}"]),
            limit=3000000, need=1)
    at = {v: c for core, c, v in r["changes"] if core == 0}
    good = r["status"][0] == "600d0000" and all(k in at for k in ("5255000a", "5255000b", "5255000c", "5255000d"))
    if not good:
        return [("DMA rate", False, f"status {r['status']}")]
    a = (at["5255000c"] - at["5255000a"]) / (ra * words)
    b = (at["5255000d"] - at["5255000b"]) / (rb * words)
    mb = lambda cpw: 50e6 * 4 / cpw / 1e6
    return [("DMA rate, DDR to tile, as the board program measures it", True,
             f"{a:.1f} cycles per word, {mb(a):.1f} MB/s at 50 MHz, including the per-transfer setup and polling"),
            ("DMA rate, tile to DDR, as the board program measures it", True,
             f"{b:.1f} cycles per word, {mb(b):.1f} MB/s at 50 MHz, including the per-transfer setup and polling")]


DEMOS = {"traffic": traffic, "dma": dma, "speedup": speedup, "restart": restart, "fixes": board_fixes,
         "dma_rate": dma_rate}


def main():
    if "--board" in sys.argv:
        sets = {"traffic": images("loop_traffic"), "dma": images("dma_lock"),
                "speedup": images("speedup", [], ["-DWORKER"]),
                "dma_rate": images("dma_rate"),
                "restart": [build_c("demo_restart", [P / "restart.c"], 0)[0],
                            build_c("demo_restart_victim", [P / "restart.c"], 1, flags=["-DVICTIM"])[0],
                            build_c("demo_restart", [P / "restart.c"], 2)[0]]}
        for name, imgs in sets.items():
            for t, m in enumerate(imgs):
                dst = BUILD / f"demo_{name}_t{t:02d}.mem"
                shutil.copy(m, dst)
            print(f"{BUILD}/demo_{name}_t00..02.mem")
        return
    names = [a for a in sys.argv[1:] if a in DEMOS] or list(DEMOS)
    out = sim()
    rows = [r for n in names for r in DEMOS[n](out)]
    lines = ["# Demo programs in simulation (NoC, 64 KB tiles)", "", "| Demo | Result | Detail |", "|---|---|---|"]
    for what, ok, detail in rows:
        print(("PASS: " if ok else "FAIL: ") + what + " -- " + detail)
        lines.append(f"| {what} | {'pass' if ok else 'FAIL'} | {detail} |")
    if len(names) == len(DEMOS):
        (HERE / "results.md").write_text("\n".join(lines) + "\n")
    sys.exit(0 if all(ok for _, ok, _ in rows) else 1)


if __name__ == "__main__":
    main()
