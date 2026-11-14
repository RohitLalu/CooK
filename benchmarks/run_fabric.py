#!/usr/bin/env python3
"""Fabric benchmark: the NoC mesh against the single shared bus under load.

    python3 benchmarks/run_fabric.py

Same endpoints on both (three tiles behind ni.v, the DMA gateway on tile 3,
a DMA model as the DDR); only the interconnect differs. Three traffic flows
that share no link on the mesh are run one at a time and then together:
see tb/tb_fabric.v. Writes results/fabric.md.
"""
import re
from cooklib import HERE, REPO, BUILD, sh

COMMON = ["benchmarks/tb/tb_fabric.v", "tb/axi_dma_model.v", "rtl/dma_ddr/gw_ni.v",
          "rtl/network_interface/ni.v", "rtl/network_interface/address_decoder.v",
          "rtl/router/link_buffer.v"]
FABRIC = {
    "noc": (["rtl/router/noc_router.v", "rtl/router/end_buff.v", "rtl/router/bist_node.v",
             "rtl/integrated/mesh/noc_mesh.v"], []),
    "bus": (["single_bus/rtl/sb_bus.v"], ["-DFABRIC_BUS"]),
}
FLOWS = [("dma", "DMA: DDR to tile 0 RAM"), ("w1", "W1: tile 1 writes tile 2's mailbox"),
         ("w2", "W2: tile 2 writes tile 1's mailbox")]


def run(arch):
    files, defs = FABRIC[arch]
    out = BUILD / f"fabric_{arch}.out"
    sh(["iverilog", "-g2012", "-Irtl/include", *defs, "-o", str(out), *COMMON, *files], cwd=REPO)
    text = sh(["vvp", "-n", str(out)]).stdout
    res = {}
    for m in re.finditer(r"FABRIC case=(\w+) dma=(\d+) w1=(\d+) w2=(\d+) total=(\d+) ok=(\d)", text):
        res[m[1]] = dict(dma=int(m[2]), w1=int(m[3]), w2=int(m[4]), total=int(m[5]), ok=m[6] == "1")
    if len(res) != 4 or "FAIL" in text:
        raise SystemExit(f"{arch}: unexpected output\n{text}")
    return res


def main():
    BUILD.mkdir(exist_ok=True)
    r = {a: run(a) for a in FABRIC}
    ok = all(c["ok"] for a in r for c in r[a].values())
    lines = ["# Fabric benchmark: mesh against shared bus under load", "",
             "Same endpoints on both fabrics; 448 words per flow; cycles from a flow's start",
             "until its last word is in the destination memory. \"Alone\" = only that flow runs,",
             "\"together\" = all three start on the same cycle. On the mesh the three flows share",
             "no link.", "",
             "| Flow | NoC alone | NoC together | NoC slowdown | Bus alone | Bus together | Bus slowdown |",
             "|---|---|---|---|---|---|---|"]
    for key, name in FLOWS:
        n1, n3 = r["noc"][key][key], r["noc"]["all"][key]
        b1, b3 = r["bus"][key][key], r["bus"]["all"][key]
        lines.append(f"| {name} | {n1} | {n3} | {n3 / n1:.2f}x | {b1} | {b3} | {b3 / b1:.2f}x |")
        print(f"{key:4s} noc {n1:6d} -> {n3:6d} ({n3 / n1:.2f}x)   bus {b1:6d} -> {b3:6d} ({b3 / b1:.2f}x)")
    nt, bt = r["noc"]["all"]["total"], r["bus"]["all"]["total"]
    ns = sum(r["noc"][k][k] for k, _ in FLOWS)
    bs = sum(r["bus"][k][k] for k, _ in FLOWS)
    lines += ["",
              "| | NoC | Bus |", "|---|---|---|",
              f"| All three together, until the last one finishes | {nt} | {bt} |",
              f"| The same three one after another (sum of the alone times) | {ns} | {bs} |",
              f"| Gain from running them together | {ns / nt:.2f}x | {bs / bt:.2f}x |",
              "", f"Every word arrived and no error flag was set: {'yes' if ok else 'NO'}."]
    print(f"together: noc {nt}, bus {bt};  one after another: noc {ns}, bus {bs};  data ok: {ok}")
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "fabric.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
