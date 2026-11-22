#!/usr/bin/env python3
"""Fault coverage of the start-up BIST: every single stuck-at fault on every
link wire and every router output wire of the 2x2 mesh, one per simulation.

    python3 benchmarks/run_coverage.py

See tb/tb_coverage.v for the fault sites. Writes results/coverage.md.
"""
import os
import re
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from cooklib import HERE, REPO, BUILD, sh

RTL = ["tb/tb_coverage.v", "rtl/integrated/mesh/noc_mesh.v", "rtl/router/noc_router.v",
       "rtl/router/link_buffer.v", "rtl/router/end_buff.v", "rtl/router/bist_node.v"]
MX = MY = 2
FW = 44                                   # NOC_FLIT_W on the default 2x2 mesh
N, S, E, W, L = 0, 1, 2, 3, 4
SITES = {1: "link data wire", 2: "link valid", 3: "link ready", 4: "router output data wire",
         5: "router output valid"}

# flit layout, lowest bit first (noc_defs.vh, 2x2): what each bit carries
def field(b):
    return ("data" if b < 32 else "dst x" if b == 32 else "dst y" if b == 33 else "src" if b < 36 else
            "type" if b < 38 else "poison" if b == 38 else "parity")


def exists(t, d):
    x, y = t % MX, t // MX
    nx, ny = x + (d == E) - (d == W), y + (d == S) - (d == N)
    return 0 <= nx < MX and 0 <= ny < MY


def faults():
    yield (0, 0, 0, 0, 0)
    for t in range(MX * MY):
        for d in range(4):
            if exists(t, d):
                for b in range(FW):
                    for v in (0, 1):
                        yield (1, t, d, b, v)
                for s in (2, 3):
                    for v in (0, 1):
                        yield (s, t, d, 0, v)
        for p in range(5):
            if p == L or exists(t, p):
                for b in range(FW):
                    for v in (0, 1):
                        yield (4, t, p, b, v)
                for v in (0, 1):
                    yield (5, t, p, 0, v)


def one(f):
    site, t, p, b, v = f
    out = BUILD / f"cov_{site}_{t}_{p}_{b}_{v}.out"
    sh(["iverilog", "-g2012", "-Irtl/include", "-s", "tb_coverage", "-o", str(out),
        f"-Ptb_coverage.SITE={site}", f"-Ptb_coverage.TILE={t}", f"-Ptb_coverage.PORT={p}",
        f"-Ptb_coverage.BIT={b}", f"-Ptb_coverage.VAL={v}", *RTL], cwd=REPO)
    r = sh(["vvp", "-n", str(out)]).stdout
    out.unlink()
    m = re.search(r"COV (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)", r)
    return tuple(map(int, m.groups()))


def main():
    BUILD.mkdir(exist_ok=True)
    fl = list(faults())
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        res = list(pool.map(one, fl))
    healthy = res[0]
    tot, hit, false = defaultdict(int), defaultdict(int), defaultdict(int)
    missed = defaultdict(list)
    for site, t, p, b, v, h, fa in res[1:]:
        tot[site] += 1; hit[site] += h; false[site] += fa > 0
        if not h:
            what = field(b) if site in (1, 4) else ""
            missed[site].append(f"tile {t} port {'NSEWL'[p]} {what} bit {b} stuck-at-{v}" if site in (1, 4)
                                else f"tile {t} port {'NSEWL'[p]} stuck-at-{v}")
    lines = ["# BIST fault coverage", "",
             "Every single stuck-at fault on the 2×2 mesh, one per simulation (`tb/tb_coverage.v`).",
             "A link fault counts as detected when every router's dead-link mask marks that",
             "link; a router fault when that router's self-test fails. False alarm: any other",
             "link or router flagged.", "",
             f"Healthy run: {'nothing flagged' if healthy[6] == 0 else 'FLAGGED SOMETHING'}.", "",
             "| Fault site | Faults | Detected | Coverage | Runs with a false alarm |",
             "|---|---|---|---|---|"]
    T = H = 0
    for s in SITES:
        lines.append(f"| {SITES[s]} | {tot[s]} | {hit[s]} | {100 * hit[s] / tot[s]:.1f} % | {false[s]} |")
        T += tot[s]; H += hit[s]
    lines += [f"| **all** | **{T}** | **{H}** | **{100 * H / T:.1f} %** | {sum(false.values())} |", ""]
    for s in SITES:
        if missed[s]:
            by = defaultdict(int)
            for m in missed[s]:
                key = re.sub(r"tile \d port \w ", "", m)
                key = re.sub(r" bit \d+", "", key)
                by[key] += 1
            lines.append(f"Undetected, {SITES[s]}: " + "; ".join(f"{k} ({n})" for k, n in sorted(by.items())) + ".")
            lines.append("")
    lines.append("<details><summary>Every undetected fault</summary>\n")
    lines += [f"- {SITES[s]}: {m}" for s in SITES for m in missed[s]]
    lines.append("\n</details>")
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "coverage.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:len(SITES) + 12]))


if __name__ == "__main__":
    main()
