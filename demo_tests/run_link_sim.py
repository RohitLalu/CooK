#!/usr/bin/env python3
"""Simulates the laptop link (demo_tests/link) and checks it against the laptop's AES.

    python3 demo_tests/run_link_sim.py            # simulate
    python3 demo_tests/run_link_sim.py --board    # only build the board images

Two messages are sent down the serial line one after the other:
  1. "show": ciphertext made on this machine; the board must decrypt it and put
     the first 8 characters on its display
  2. "encrypt": plaintext; the board must answer with the ciphertext this
     machine's AES also produces
Board images: benchmarks/build/link_board_tNN.mem (64 KB tiles, UART_EN = 1).
"""
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "benchmarks"))
sys.path.insert(0, str(HERE / "link"))
from cooklib import BUILD, OB, REPO, RTL, RTL_SHARED, build_c, sh   # noqa: E402
import laptop                                                        # noqa: E402

C = HERE.parent / "benchmarks" / "crypto"
PROGS = [("link_core0", [HERE / "link" / "core0_link.c", C / "sha256.c"]),
         ("link_aes",   [C / "core1_aes.c", C / "aes128.c"]),
         ("link_sign",  [C / "core2_sign.c", C / "sha256.c", C / "wots.c"])]


def main():
    board = "--board" in sys.argv
    images = [build_c(name + ("_board" if board else ""), srcs, tile, flags=[f"-I{C}"])
              for tile, (name, srcs) in enumerate(PROGS)]
    if board:
        for tile, (mem, size) in enumerate(images):
            dst = BUILD / f"link_board_t{tile:02d}.mem"
            shutil.copy(mem, dst)
            print(f"{dst}  ({size} bytes of program)")
        return

    show, enc = laptop.pad("HELLO NOC"), laptop.pad("computed in the FPGA")
    frames = laptop.frame(1, laptop.aes(show)) + laptop.frame(2, enc)
    expect = bytes([0x5A, 0, 0]) + bytes([0x5A, 0, len(enc)]) + laptop.aes(enc)
    ff = BUILD / "link_frames.hex"
    ff.write_text("".join(f"{b:02x}\n" for b in frames))

    out = BUILD / "link.out"
    sh(["iverilog", "-g2012", "-Irtl/include", f"-DNOC_OFFSET_BITS={OB}", "-s", "tb_link", "-o", str(out),
        "demo_tests/tb/tb_link.v", "demo_tests/rtl/uart_port.v", *RTL_SHARED, *RTL["noc"]], cwd=REPO)
    text = sh(["vvp", "-n", str(out), *[f"+img{t}={m}" for t, (m, _) in enumerate(images)],
               f"+frame={ff}", f"+nbytes={len(frames)}", f"+nreply={len(expect)}"]).stdout
    reply = bytes.fromhex(re.search(r"LINK reply=(\w*)", text)[1])
    m = re.search(r"LINK text=(\w+) en=(\d) status0=(\w+) trap=(\d+) cycles=(\d+)", text)
    shown = bytes.fromhex(m[1])[::-1]                 # character 0 is the low byte
    checks = [
        (reply[:3] == expect[:3], "show: board answered ok"),
        (m[2] == "1" and shown == show[:8], f"show: display reads {shown!r}, expected {show[:8]!r}"),
        (reply[3:] == expect[3:], "encrypt: ciphertext from the board equals the laptop's AES"),
        (m[3].startswith("600d0002") and m[4] == "000", "core 0 served two messages, no core trapped"),
    ]
    for ok, what in checks:
        print(("PASS: " if ok else "FAIL: ") + what)
    print(f"      {m[5]} cycles after the last byte was sent; reply {reply.hex()}")
    sys.exit(0 if all(ok for ok, _ in checks) else 1)


if __name__ == "__main__":
    main()
