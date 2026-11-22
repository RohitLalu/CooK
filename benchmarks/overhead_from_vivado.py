#!/usr/bin/env python3
"""Area of each part of the NoC, from Vivado's hierarchical utilisation report.

    python3 benchmarks/overhead_from_vivado.py cook_vivado/out/util_hier_gw1.rpt

The report is written by cook_vivado/build.tcl (report_utilization
-hierarchical). This sums the LUTs, flip-flops and block RAM of every
instance of each module and writes results/overhead.md, with the BIST's share
of the network and of the whole design. Yosys estimates are not used: on this
design they come out several times higher than Vivado's.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
GROUPS = [("BIST node (link test, router self-test, gossip)", "bist_node"),
          ("Router", "noc_router"), ("Link buffer", "link_buffer"),
          ("Network interface", "ni"), ("DMA gateway", "gw_ni"),
          ("PicoRV32 core", "picorv32"), ("Status panel and display", "status_panel"),
          ("Block design (DMA, SmartConnect, MIG)", "cook_gw")]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    text = Path(sys.argv[1]).read_text()
    rows = [l for l in text.splitlines() if l.startswith("|")]
    head = [c.strip() for c in rows[0].strip("|").split("|")]
    col = {n: i for i, n in enumerate(head)}
    lut = next(i for n, i in col.items() if n.startswith("Total LUTs"))
    ff = col.get("FFs")
    bram = col.get("RAMB36") or next((i for n, i in col.items() if "RAMB36" in n), None)
    tot = defaultdict(lambda: [0, 0, 0.0, 0])
    top = None
    for l in rows[1:]:
        cells = [c.strip() for c in l.strip("|").split("|")]
        if not cells or not cells[lut].isdigit():
            continue
        inst, mod = cells[0], (cells[1] if len(cells) > 1 else "")
        vals = [int(cells[lut]), int(cells[ff]) if ff is not None else 0,
                float(cells[bram]) if bram is not None and cells[bram] else 0.0]
        if top is None:
            top = vals
            continue
        base = re.sub(r"__parameterized\d+$", "", mod)           # Vivado's name for a parameter variant
        for name, key in GROUPS:
            if base == key or base.startswith(key + "_wrapper"):
                t = tot[name]
                t[0] += vals[0]; t[1] += vals[1]; t[2] += vals[2]; t[3] += 1
                break
    noc = sum(tot[n][0] for n, _ in GROUPS[:3])
    lines = ["# Area per module (Vivado)", "", f"From `{sys.argv[1]}`. Totals over every instance of each module.", "",
             "| Part | Instances | LUTs | FFs | RAMB36 | Share of the design's LUTs |", "|---|---|---|---|---|---|"]
    for name, _ in GROUPS:
        t = tot[name]
        if t[3]:
            lines.append(f"| {name} | {t[3]} | {t[0]:,} | {t[1]:,} | {t[2]:g} | {100 * t[0] / top[0]:.1f} % |")
    lines.append(f"| **Whole design** | | **{top[0]:,}** | **{top[1]:,}** | **{top[2]:g}** | 100 % |")
    b = tot[GROUPS[0][0]][0]
    if noc:
        lines += ["", f"BIST share of the network (BIST + routers + link buffers): {100 * b / noc:.1f} % of its LUTs."]
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "overhead.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
