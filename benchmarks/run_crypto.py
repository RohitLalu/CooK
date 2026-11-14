#!/usr/bin/env python3
"""The three-core crypto demo on both architectures (benchmarks/crypto/).

    python3 benchmarks/run_crypto.py            # simulate on the NoC and on the bus
    python3 benchmarks/run_crypto.py --board    # only build the full-size board images

Core 0 generates the keys and hands out the work, core 1 does AES-128,
core 2 signs (WOTS over SHA-256); see crypto/proto.h. Simulation uses the
small signature size (WOTS_LOGW=2, WOTS_N=1), because a SHA-256 block costs
tens of thousands of cycles on this core and Icarus runs about 1500 cycles
per second. The board images use the full size (LOGW 8, N 32).
Writes results/crypto.md; board images go to build/crypto_board_tNN.mem.
"""
import shutil
import sys
from cooklib import HERE, BUILD, build_c, build_sim, run

C = HERE / "crypto"
PROGS = [("crypto_arbiter", ["core0_arbiter.c", "sha256.c", "wots.c"]),
         ("crypto_aes",     ["core1_aes.c", "aes128.c"]),
         ("crypto_sign",    ["core2_sign.c", "sha256.c", "wots.c"])]


def build(flags, tag):
    return [build_c(f"{name}{tag}", [C / f for f in srcs], tile, flags=[f"-I{C}", *flags])
            for tile, (name, srcs) in enumerate(PROGS)]


def main():
    if "--board" in sys.argv:
        for tile, (mem, size) in enumerate(build([], "_board")):
            dst = BUILD / f"crypto_board_t{tile:02d}.mem"
            shutil.copy(mem, dst)
            print(f"{dst}  ({size} bytes of program)")
        return
    images = build(["-DWOTS_LOGW=2", "-DWOTS_N=1"], "_sim")
    lines = ["# Three-core crypto demo on both architectures", "",
             "Core 0: keys and arbiter. Core 1: AES-128 encrypt, then decrypt. Core 2: WOTS",
             "signature (simulation size: `WOTS_LOGW=2`, `WOTS_N=1`). Pass means core 0 got the",
             "plaintext back from the decrypt, the signature verified, and a changed message was",
             "rejected.", "",
             "| Arch | Result | Cycles | Core 0 status | Core 1 status | Core 2 status | Flits on the interconnect |",
             "|---|---|---|---|---|---|---|"]
    # healthy, then with one fault from reset. NoC: the link leaving tile 0
    # eastward goes silent, which is the direct link between the arbiter and
    # the AES core; BIST finds it and their traffic goes round by tiles 2 and
    # 3. Bus: the arbiter is stuck. In the bus fault run only core 0's verdict
    # is awaited, because the workers never get a job.
    cases = [("noc", "healthy", []), ("bus", "healthy", []),
             ("noc", "link 0-1 dead", ["+fault=0004"]),
             ("bus", "arbiter stuck", ["+fault=1", "+need=1"])]
    sims = {a: build_sim(a, tag="crypto") for a in ("noc", "bus")}
    for arch, what, extra in cases:
        r = run(sims[arch], [m for m, _ in images], limit=12_000_000, extra=extra)
        st = (r["status"] + ["-", "-"])[:3]
        print(f"{arch} {what}: {r['verdict']}  {r['cycles']} cycles  status {st}  flits {r['flits']}", flush=True)
        lines.append(f"| {arch}, {what} | {r['verdict']} | {r['cycles']} | {' | '.join(st)} | {r['flits']} |")
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "crypto.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
