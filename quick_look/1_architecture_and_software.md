# CooK in plain words: architecture, software and tests

## The one-paragraph idea

CooK is a tiny computer system on one chip, built to keep working when part of it breaks. Think of a small town with four houses on a square of streets. Three houses each have a worker (a small processor). The fourth is a warehouse door leading to a huge storage building. Workers send each other letters along the streets. Every morning, inspectors test each street before anyone leaves home. If a street is broken, the traffic police route around it and the town carries on.

Most chips connect their processors with a single shared bus, like a town with one road. Break that road and everything stops. Our town has other ways round. That is the whole point of the project, and it is what we measure.

## The town map

| Town | Real part | File |
|---|---|---|
| Worker | PicoRV32 RISC-V processor core | `rtl/core/picorv32.v` |
| House's mail room | Network Interface (NI) | `rtl/network_interface/ni.v` |
| Intersection with a traffic cop | Router | `rtl/router/noc_router.v` |
| Street, with a waiting lane | Link buffer | `rtl/router/link_buffer.v` |
| Morning street inspector | BIST node (Built-In Self-Test) | `rtl/router/bist_node.v` |
| Warehouse door and front office | Gateway NI | `rtl/dma_ddr/gw_ni.v` |
| Warehouse and forklift | DDR2 memory and Xilinx AXI DMA | `rtl/dma_ddr/create_cook_gw.tcl` |
| Town layout | Mesh generator | `rtl/integrated/mesh/noc_mesh.v` |
| Town rulebook | Shared constants | `rtl/include/noc_defs.vh` |
| Dashboard | LEDs and display | `rtl/board/status_panel.v` |

Houses are numbered like reading a book. Tile 0 and tile 1 are on the top row, tile 2 and tile 3 on the bottom. Tile 3 is the gateway. The town also works as four ordinary worker houses with no warehouse, which we use for the first board test.

## How a letter travels

Say the worker in tile 0 wants a number stored in tile 3.

1. **The worker just asks for an address.** It has no idea a network exists. Each house owns 4 KB of addresses, so the top of the address names the house.
2. **The mail room checks the address.** If it is local, it answers straight away. If it is remote, it writes a letter.
3. **The letter is two pieces**, called flits: a HEAD (the envelope, with destination, sender and what is wanted) and a TAIL (the contents). Each flit is 44 bits, including parity bits that catch damage, like a checksum on a parcel.
4. **Traffic cops forward it.** The normal rule is X-Y routing: go across first, then down. Because nobody ever turns from down back to across, cars can never end up in a circle all waiting for each other. That kind of jam is called deadlock.
5. **The other mail room answers by itself.** Its worker does not have to stop. This matters: a house can answer even if its worker is doing something else.
6. **If no answer comes,** the mail room waits, then sends again with a new ticket number. After a few tries, it hands the worker a special "this failed" value (`0xDEADBEEF`) and raises a flag. The worker never hangs forever.

Three traffic rules keep the streets orderly:
- **A letter is not allowed to mix with another.** Once a HEAD takes an exit, that exit is locked until its TAIL passes.
- **Don't enter unless the whole letter fits.** The cop checks the waiting lane has room first. So a stuck exit means something is truly broken, not just busy.
- **Cops have stopwatches.** An exit that makes no progress for too long gets its letter closed off with a "damaged" mark, or gets marked dead.

## The morning inspection (BIST)

This runs in hardware after every full reset, before any worker is allowed to start. It takes about 330 clock ticks, under 7 microseconds on the board.

1. **Ping-pong.** Each cop sends 6 test words down each street: all zeros, all ones, alternating. A wire stuck at 0 or 1 cannot pass both. The neighbour checks them and sends one "pong" back. Each cop records what passed in a 10-bit report.
2. **Sharing the closed-road list.** Cops pass a list of dead streets to their neighbours over good streets only, for four rounds, until everyone has the same list.
3. **Going around.** Both ends stop using a dead street. Our four streets form a ring (0-1-3-2-0), so a letter simply goes the other way round. Remove one street from a ring and you have a line, which cannot form a circle, so this cannot cause a deadlock.
4. **Roll call.** The gateway reads every house's report over the network. A house counts as available only if that read comes back correct. Only then do the workers start.

Two results are easy to mix up, and they go to different places:

- The **closed-road list** goes to every router. It is what steers traffic.
- The **availability bitmap** stays in the gateway's office (register `0x120`). The gateway uses it to refuse warehouse jobs. A worker only sees it if its program looks it up.

**The result we measure (M3):** for every single broken street, in both directions and both failure styles (silent, or scrambling bits), all 3 of 3 workers keep working. A single-road bus design would have 0 of 3.

## The warehouse (DMA)

The workers share one forklift, so there are rules, all enforced in hardware at the gateway:
- **One key.** A worker claims the forklift by reading a register (the lock). Others queue in turn.
- **The key expires.** If the owner goes quiet for 16,384 ticks, the lock is taken back, so a dead worker can't block everyone.
- **Your own shelves only.** The 128 MB warehouse has three 40 MB zones (one per worker) and two 4 MB shared areas.
- **Refusals come with a reason.** A bad request is rejected with a reason number instead of being carried out.

Separately, other houses can only write into a small mailbox (`0x800` to `0xEFF`) in each house's memory, so a confused neighbour can't overwrite your program.

## The software

A worker runs a program stored in its house's memory. We write programs in assembly (`sw/*.S`), which is the worker's own language. The script `sw/build.sh` turns each into a `.mem` file, a plain list of numbers. That file gets loaded into memory when the chip is built, so the program is already there at power-on.

| Program | What it does |
|---|---|
| `alltoall.S` | Every worker tests every other worker: 74 checks per worker, including byte writes, patterns and even running code from another house's memory |
| `hammer.S` | Rush hour: lots of letters at once, to force traffic to share streets |
| `tile0.S` | A few specific reads, including a deliberately bad address |
| `spin.S` | Does nothing, forever |

`alltoall.S` is what runs on the board. It first asks the gateway for the bitmap and skips houses marked unavailable. Then it writes a score to its status register: `0x600D....` for pass or `0xFA11....` for fail. The board's LEDs show those.

BIST itself uses no software. The only software link is that one optional lookup. C programs and a proper linker script come later, with the compiler work.

## How the testbenches work

A testbench is a pretend world built around the real part, like a crash-test lab around a real car. It is ordinary Verilog that never goes on the chip. Nearly all of ours follow the same recipe:

1. **Make a clock and hold reset**, then release it.
2. **Build the part** being tested (the "DUT", device under test).
3. **Fake whatever is missing.** The router test uses queues for incoming letters and logs for outgoing ones. The gateway test uses `tb/axi_dma_model.v` as a pretend forklift.
4. **Run scenarios** and check results with a small `check(condition, "message")` task, which prints `PASS` or `FAIL`.
5. **Print a total.** The Makefile fails the run if the word `FAIL` appears anywhere.

**Breaking things on purpose.** A link buffer can be told to go silent or flip a bit. That can be set at build time, or live by the board's switches. This is how we test faults without damaging hardware.

We test from small to large, like checking a brick, then a wall, then a house:

| Level | Testbench | Checks | What it proves |
|---|---|---|---|
| Parts | `tb_address_decoder`, `tb_link_buffer` | 17, 229 | Addresses and waiting lanes behave |
| Router | `tb_noc_router` | 159 | Routing, locks, drops, stopwatches. Plus 2 Python tests in `cocotb/` as a second opinion |
| Mail room | `tb_ni` | 56 | Requests, retries, mailbox rule |
| Inspection | `tb_bist` | 12 | Five towns side by side, each with a different fault; every report compared |
| Whole town | `tb_mesh_top` | 14, 8, 8, 6, 14, 10, 15 | Real workers running real programs, healthy, faulted, and on a 3×3 town |
| Warehouse | `tb_gw_ni`, `tb_gw_alltoall` | 41, 8, 7, 11 | Lock, zones, every refusal, broken paths |
| Dashboard | `tb_status_panel` | 57 | Blink codes and which error shows first |
| Board | `tb_board` | 11, 9 | The whole chip design; results read only from the LEDs |
| The headline | `tb_m3` | 19 | Every broken street, both styles, plus two double faults |

`tb_gw_dma_ip` is the one test that needs Vivado, because it uses the real Xilinx forklift.

**Testing the tests.** A test that can't fail is worthless. So we sometimes break the design on purpose, for example by turning the detour off, and confirm the tests go red. They did, each time we tried.

Run everything with `make test` (a few minutes). `make synth_check` also checks that the design can be turned into real hardware without accidental memory (latches) or logic loops.

**All of this is simulation.** It has not yet run on the real board. That is what `3_testing_on_nexys4.md` is for.
