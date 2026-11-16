#!/usr/bin/env python3
"""Simulates the laptop link (encryption_code/link) and checks it against the laptop's AES.

    python3 encryption_code/run_link_sim.py            # simulate
    python3 encryption_code/run_link_sim.py --board    # only build the board images
    python3 encryption_code/run_link_sim.py --top      # the same test through nexys4ddr_live_top,
                                                       # at the real baud rate, read from the display pins

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

C = HERE / "crypto"
PROGS = [("link_core0", [HERE / "link" / "core0_link.c", C / "sha256.c"]),
         ("link_aes",   [C / "core1_aes.c", C / "aes128.c", C / "sha256.c"]),
         ("link_sign",  [C / "core2_sign.c", C / "sha256.c", C / "wots.c"])]


def main():
    live = "--top" in sys.argv
    board = "--board" in sys.argv or live
    images = [build_c(name + ("_board" if board else ""), srcs, tile, flags=[f"-I{C}"])
              for tile, (name, srcs) in enumerate(PROGS)]
    if board:
        for tile, (mem, size) in enumerate(images):
            dst = BUILD / f"link_board_t{tile:02d}.mem"
            shutil.copy(mem, dst)
            print(f"{dst}  ({size} bytes of program)")
        if not live:
            return

    show, enc = laptop.pad("HELLO NOC"), laptop.pad("computed in the FPGA")
    frames = laptop.frame(1, laptop.aes(show)) + laptop.frame(2, enc)
    expect = bytes([0x5A, 0, 0]) + bytes([0x5A, 0, len(enc)]) + laptop.aes(enc)
    ff = BUILD / "link_frames.hex"
    ff.write_text("".join(f"{b:02x}\n" for b in frames))

    out = BUILD / ("link_top.out" if live else "link.out")
    defs = ["-DLINK_LIVE_TOP"] if live else []
    extra = (["encryption_code/rtl/nexys4ddr_live_top.v", "encryption_code/rtl/seven_seg_text.v",
              "rtl/board/nexys4ddr/nexys4ddr_top.v", "rtl/board/reset_sync.v", "rtl/board/status_panel.v",
              "rtl/board/seven_seg.v"] if live else [])
    sh(["iverilog", "-g2012", "-Irtl/include", f"-DNOC_OFFSET_BITS={OB}", *defs, "-s", "tb_link", "-o", str(out),
        "encryption_code/tb/tb_link.v", "encryption_code/rtl/uart_port.v", *extra, *RTL_SHARED, *RTL["noc"]],
       cwd=REPO)
    text = sh(["vvp", "-n", str(out), *[f"+img{t}={m}" for t, (m, _) in enumerate(images)],
               f"+frame={ff}", f"+nbytes={len(frames)}", f"+nreply={len(expect)}", "+limit=6000000"],
              cwd=REPO).stdout
    reply = bytes.fromhex(re.search(r"LINK reply=(\w*)", text)[1])
    m = re.search(r"LINK text=(\w+) en=(\d) status0=(\w+) trap=(\d+) cycles=(\d+)", text)
    if live:
        # the testbench read 7-segment patterns off the pins, leftmost digit first
        font = {0x76: "H", 0x79: "E", 0x38: "L", 0x5C: "O", 0x54: "N", 0x00: " "}
        shown = "".join(font.get(b, "?") for b in bytes.fromhex(m[1])).encode()
    else:
        shown = bytes.fromhex(m[1])[::-1]             # character 0 is the low byte
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
