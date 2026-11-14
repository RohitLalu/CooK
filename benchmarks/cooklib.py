"""Shared helpers for the benchmark runners: build a C program for one tile,
build the two simulators, run an image set and read the result."""
import re
import struct
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
BUILD = HERE / "build"
CRT = HERE / "crt"
OB = 16                       # NOC_OFFSET_BITS of the benchmark build: 64 KB per tile
MEM_WORDS = 1 << (OB - 2)
CLK_HZ = 50_000_000           # the board's system clock
CC = "riscv64-unknown-elf-gcc"
OC = "riscv64-unknown-elf-objcopy"
ARCH = ["-march=rv32i", "-mabi=ilp32"]

RTL_SHARED = ["rtl/router/link_buffer.v", "rtl/network_interface/address_decoder.v",
              "rtl/network_interface/ni.v", "rtl/core/picorv32.v"]
RTL = {
    "noc": ["rtl/router/noc_router.v", "rtl/router/end_buff.v", "rtl/router/bist_node.v",
            "rtl/integrated/mesh/noc_mesh.v", "rtl/integrated/mesh/mesh_top.v", "rtl/dma_ddr/gw_ni.v"],
    "bus": ["single_bus/rtl/sb_bus.v", "single_bus/rtl/sb_mem_ni.v", "single_bus/rtl/sb_top.v",
            "single_bus/tb/axi4_mem_model.v"],
}


def sh(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode:
        raise SystemExit(f"command failed: {' '.join(map(str, cmd))}\n{r.stdout}{r.stderr}")
    return r


def to_mem(elf, mem, ob=OB):
    """ELF -> full-tile $readmemh image (program from word 64) for 2**ob-byte
    tiles. Returns bytes used."""
    words = 1 << (ob - 2)
    binf = Path(elf).with_suffix(".bin")
    sh([OC, "-O", "binary", str(elf), str(binf)])
    data = binf.read_bytes()
    data += b"\0" * (-len(data) % 4)
    prog = [w for (w,) in struct.iter_unpack("<I", data)]
    if len(prog) > words - 64:
        raise SystemExit(f"{elf}: {len(prog)} words do not fit in a tile")
    img = [0] * 64 + prog + [0] * (words - 64 - len(prog))
    Path(mem).write_text("".join(f"{w:08x}\n" for w in img))
    return len(data)


def build_c(name, sources, tile, flags=(), opt="-O2"):
    """Compile and link a C program for one tile with crt/. Returns (mem path, bytes)."""
    BUILD.mkdir(exist_ok=True)
    stem = BUILD / f"{name}_t{tile}"
    sh([CC, *ARCH, opt, "-ffreestanding", "-fno-builtin", "-nostdlib", "-nostartfiles", "-static",
        "-ffunction-sections", "-fdata-sections", "-Wl,--gc-sections",
        f"-DTILE_SHIFT={OB}", f"-I{CRT}", *flags,
        f"-T{CRT / 'tile.ld'}", f"-Wl,--defsym,TILE_BASE={tile << OB:#x}",
        f"-Wl,--defsym,TILE_SIZE={1 << OB:#x}", "-Wl,--build-id=none",
        "-o", f"{stem}.elf", str(CRT / "crt0.S"), str(CRT / "libmin.c"), *map(str, sources), "-lgcc"])
    return f"{stem}.mem", to_mem(f"{stem}.elf", f"{stem}.mem")


def build_sim(arch, defines=(), tag="bench", ob=OB):
    """Compile tb_bench for one architecture. `tag` names the output, so two
    runners can work at the same time without sharing a simulator file."""
    BUILD.mkdir(exist_ok=True)
    out = BUILD / f"{tag}_{arch}.out"
    sh(["iverilog", "-g2012", "-Irtl/include", f"-DNOC_OFFSET_BITS={ob}",
        *(["-DBENCH_BUS"] if arch == "bus" else []), *defines,
        "-s", "tb_bench", "-o", str(out), "benchmarks/tb/tb_bench.v", *RTL_SHARED, *RTL[arch]], cwd=REPO)
    return out


def run(sim, images, limit=400000, extra=()):
    """Run one image per core tile; a tile given None has no program, traps at
    once and is left out of the verdict. Returns dict(cycles, status, verdict, ...)."""
    r = sh(["vvp", "-n", str(sim), *[f"+img{t}={m}" for t, m in enumerate(images) if m],
            f"+limit={limit}", *extra])
    m = re.search(r"BENCH cycles=(\d+) st0=(\w+) st1=(\w+) st2=(\w+) trap=(\d+) bus=(\d+)", r.stdout)
    if not m:
        raise SystemExit("no BENCH line:\n" + r.stdout)
    used = [t for t, im in enumerate(images) if im]
    for e in extra:                                  # +need=<mask>: only those cores are judged
        if e.startswith("+need="):
            used = [t for t in used if int(e[6:]) >> t & 1]
    st = [[m[2], m[3], m[4]][t] for t in used]
    if any(m[5][2 - t] == "1" for t in used):
        verdict = "TRAP"
    elif all(s.startswith("600d") for s in st):
        verdict = "pass"
    elif any(s.startswith("fa11") for s in st):
        verdict = "FAIL " + ",".join(s[4:] for s in st if s.startswith("fa11"))
    else:
        verdict = "TIMEOUT"
    return dict(cycles=int(m[1]), status=st, trap=m[5], flits=int(m[6]), verdict=verdict, out=r.stdout)
