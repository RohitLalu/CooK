# CooK in plain words: architecture, software and tests

> **Status: COMPLETE** (2026-11-16). Matches the system as of this date.

## The one-paragraph idea

CooK is a tiny computer system on one chip, built to keep working when part of it breaks. Think of a small town with four houses on a square of streets. Three houses each have a worker (a small processor). The fourth is a warehouse door leading to a huge storage building. Workers send each other letters along the streets. Every morning, inspectors test each street and each intersection before anyone leaves home. If something is broken, traffic is sent round it and the town carries on.

Most chips connect their processors with a single shared bus, like a town with one road. Break that road and everything stops. We built that one-road town too, as a comparison, and we measure both.

## The town map

| Town | Real part | File |
|---|---|---|
| Worker | PicoRV32 RISC-V processor core | `rtl/core/picorv32.v` |
| House's mail room | Network Interface (NI) | `rtl/network_interface/ni.v` |
| Intersection with a traffic cop | Router | `rtl/router/noc_router.v` |
| Street, with a waiting lane | Link buffer | `rtl/router/link_buffer.v` |
| Morning inspector | BIST node (Built-In Self-Test) | `rtl/router/bist_node.v` |
| Warehouse door and front office | Gateway NI | `rtl/dma_ddr/gw_ni.v` |
| Warehouse and forklift | DDR2 memory and Xilinx AXI DMA | `rtl/dma_ddr/` |
| Town layout | Mesh generator | `rtl/integrated/mesh/noc_mesh.v` |
| Dashboard | LEDs and display | `rtl/board/status_panel.v` |
| The one-road town | Single-bus baseline | `single_bus/` |

Houses are numbered like reading a book: tiles 0 and 1 on the top row, 2 and 3 below. Tile 3 is the gateway.

## How a letter travels

Say the worker in tile 0 wants a number stored in tile 3.

1. **The worker just asks for an address.** It has no idea a network exists. The top of the address names the house.
2. **The mail room checks the address.** Local: it answers at once. Remote: it writes a letter.
3. **The letter is two pieces**, called flits: a HEAD (the envelope) and a TAIL (the contents). Each carries parity bits that catch damage, like a checksum on a parcel.
4. **Traffic cops forward it.** The rule is X-Y routing: go across first, then down. Nobody ever turns from down back to across, so cars can never end up in a circle all waiting for each other. That jam is called deadlock.
5. **The other mail room answers by itself.** Its worker does not have to stop.
6. **If no answer comes,** the mail room tries again, and after three tries hands the worker a special "this failed" value (`0xDEADBEEF`) and raises a flag. The worker never waits forever.

Three traffic rules keep order: a letter can't be mixed with another (its exit is reserved until its TAIL passes); a letter only enters a street if the whole of it fits; and cops have stopwatches, so an exit that makes no progress is closed off.

## The morning inspection (BIST)

This runs in hardware after every full reset, before any worker starts. It takes about 545 clock ticks, around 11 millionths of a second.

1. **Streets.** Each cop sends test words down each street, all zeros and all ones. A stuck wire can't pass both. The neighbour checks them and answers.
2. **Intersections.** Each cop is then tested from the inside: a test letter is pushed in at every entrance, for every exit, and must come out of the right exit, whole and unchanged. Two letters are also sent at once, to check they don't get shuffled together.
3. **The closed-road list.** Cops pass a list of dead streets to their neighbours over good streets only, until everyone has the same list. A cop that failed its own test puts all its streets on the list.
4. **Going around.** Our four streets form a ring. With one street closed, traffic simply goes the other way round. A ring with a piece missing is a line, which can't form a circle, so this can't cause a deadlock.
5. **Roll call.** The gateway reads every house's report over the network. A house counts as available only if that read really arrives. Only then do the workers start.

Two results go to different places. The **closed-road list** goes to every router and steers traffic. The **availability list** stays in the gateway's office, where it is used to refuse warehouse jobs.

**What this gives:** any single broken street, and all three workers still work. A broken intersection costs only its own house. In the one-road town, one fault stops everyone.

## The warehouse (DMA)

The workers share one forklift, with rules enforced in hardware at the gateway: one key (a lock), handed round in turn; the key expires if its holder goes quiet; each worker may only use its own shelves; and a bad request is refused with a reason number.

## Keeping houses private

- **Other houses can only write into your mailbox,** a small marked area. They can't touch your program.
- **Optionally, they can only read your mailbox too.** With this switched on, a neighbour who tries to read your private notes gets the "failed" value.
- **Messages carry a secret stamp.** Workers who share a secret word add a stamp computed from it. A message with a wrong stamp is ignored. This is done by the programs, not the hardware.
- **A worker who collapses can be woken.** Any house can see that another worker has stopped and restart it. On a restart the worker's notes are put back to how they were at power-on.

## One thing left to the programs

There is no hardware rule that stops two workers writing the same shared note at the same moment. The warehouse has its lock; shared notes do not. Today every shared note has exactly one writer, so nothing goes wrong. A program that breaks that habit would corrupt data without any warning. This was a deliberate choice: it keeps the hardware small and lets programs decide the rules.

## The software

A worker runs a program stored in its house's memory. Small test programs are written in assembly (`sw/*.S`). Larger ones are written in C, with a small start-up file and a memory plan (`benchmarks/crt/`) that keep the program clear of the mailbox.

| Program | What it does |
|---|---|
| `alltoall.S` | Every worker tests every other worker: 74 checks each |
| Standard processor tests | Two public test suites, checked against a reference simulator, to show the workers compute correctly |
| Dhrystone, CoreMark | Standard speed tests for a single worker |
| Crypto demo | Worker 0 makes keys and hands out jobs; worker 1 encrypts with AES; worker 2 signs a message. Each keeps its working data at home |
| Demos | Never-ending traffic, sharing work for speed, warehouse turns, restarting a worker, and a laptop link |

## How the testbenches work

A testbench is a pretend world built round the real part, like a crash-test lab round a real car. It never goes on the chip. Nearly all of ours follow one recipe:

1. Make a clock, hold reset, release it.
2. Build the part being tested.
3. Fake whatever is missing. A pretend forklift stands in for the real one; pretend workers stand in for processors when we want traffic faster than a real worker can make it.
4. Run scenarios and check each result. The run fails if the word `FAIL` appears anywhere.

**Breaking things on purpose.** A street can be told to go silent or scramble bits, and an intersection can be told to corrupt what it sends. That is how we test faults without damaging hardware.

We test from small to large:

| Level | What it proves |
|---|---|
| Parts | Addresses, waiting lanes, one router, one mail room |
| Inspection | Six towns side by side, each with a different fault, every report compared |
| Whole town | Real workers running real programs, healthy and faulted |
| Random traffic with a scorekeeper | Every house sends random letters at once; every answer is checked against a record of what should be there. No letter lost, none duplicated, nothing stuck |
| Fault sweep | Every street broken in turn, both ways, plus a broken intersection |
| Board | The whole design, read only from the LEDs |

**Testing the tests.** A test that can't fail is worthless. So we break the design on purpose, for example by making a cop route the wrong way, and confirm the tests go red.

## NoC against one road: what we measured

- **One letter at a time:** no difference. The mail room, not the road, is the limit.
- **Three streams at once on different streets:** the town finishes in 1,807 ticks; the one-road town needs 2,697.
- **Nine houses all sending random letters:** the town takes 13,513 ticks, the one-road town 27,398. The town with four houses took almost the same time as with nine; the one road took twice as long.
- **One fault:** all three workers still usable in the town, none on the one road.
- **A single worker's speed:** identical on both, because a worker computing at home doesn't use the streets.

The town wins when several things happen at once on different streets, and when something breaks. It does not win on a single errand.

## Where this stands

The first board test, on 7 November, passed for the design as it was then. Everything added since (the intersection test, privacy options, restart, the laptop link, larger house memories) passes in simulation and still has to be built and run on the board.
