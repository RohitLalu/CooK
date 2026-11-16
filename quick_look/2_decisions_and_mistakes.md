# Why it is built this way: decisions and mistakes

> **Status: COMPLETE** (2026-11-16). Matches the system as of this date.

The town analogy from `1_architecture_and_software.md` is used here too: houses are tiles, streets are links, traffic cops are routers, mail rooms are network interfaces (NIs).

## Part 1: The decisions

Each decision had a real alternative. The "cost" column is what we gave up, because every choice has one.

### The big shape

| Decision | Why | Cost |
|---|---|---|
| **A grid of streets, not one shared road (a bus)** | Break a bus and everyone stops, with no way to find out why. A grid has other ways round | Slower for so few workers: about 30–40 ticks for a remote read against 1–3 on a bus. We say so openly. We win on survival, not speed |
| **Build on a 2018 thesis, then add one new thing** | The thesis found broken links but did nothing with the result. Our new contribution is that test results decide, in hardware, who may move data | The project is judged on that link, so it has to really work |
| **Only 4 houses** | It fits the board and is small enough to understand fully. Size is a setting, so a 3×3 town also runs | Detours currently work on 2×2 only |

### The streets and letters

| Decision | Why | Cost |
|---|---|---|
| **Waiting lanes on streets, not letter-bouncing** | We considered a "bufferless" network where a letter with no room gets sent the wrong way. Waiting lanes are simpler, and a blocked letter just waits | Some memory on every street |
| **Reserve the exit until the whole letter passes** | Stops two letters getting shuffled together | A long letter holds up others |
| **Only enter when the whole letter fits** | Then a stuck exit means real damage, not traffic. Lets the stopwatch tell the two apart | Slightly less efficient use of space |
| **X-Y routing, no extra lanes** | Simple, and it mathematically cannot deadlock | Only one normal path, which is why broken streets needed a special plan |
| **Full destination on every letter** | Cops don't rewrite letters, so a parity check made at the start still holds at the end | A few extra bits |
| **Parity, damage marks, stopwatches, retries** | Each catches what the last one misses, from fastest to slowest | More logic. Writes get no reply, so a lost write can't be retried |
| **All settings in one rulebook (`noc_defs.vh`), plain Verilog** | The earlier hand-wired version collected a long list of crossed wires. Now every width comes from one place. The team chose not to use SystemVerilog | Verilog is a little clumsier |

### The processor and warehouse

| Decision | Why | Cost |
|---|---|---|
| **Use PicoRV32 as is** | The processor isn't the research question | One part we didn't write |
| **Its simple memory signals, not AXI, inside the town** | The worker sends one request at a time, which suits a letter stream. AXI has five separate channels we'd only be flattening again | AXI appears only at the warehouse door |
| **Xilinx's free DMA, not our own** | Reliable, standard, and small | We depend on Vivado to test it |
| **A single lock with a turn order and an expiry** | Claiming by *reading* is safe even if the mail room retries, since asking twice changes nothing. Expiry means a dead worker can't keep the key | 16,384 ticks was a judgment call. It must outlast the retries (3 × 1024 ticks) |
| **Warehouse zones: 3 × 40 MB plus 2 × 4 MB shared** | Workers can't scribble over each other, and shared areas give an agreed place to swap data | Fixed split. Changing it means changing settings and rebuilding |
| **Mailbox window, not separate memories** | Simple protection against a confused neighbour. A future linker script will place code outside it | Reads stay open, and writes to registers stay open |
| **New error codes B, C, D, E** | The dashboard can say exactly what went wrong | Codes above 9 take long to count by blink, so read the display |

### The inspection

| Decision | Why | Cost |
|---|---|---|
| **Inspectors at every intersection, boss at the gateway** | Only local cops can test local streets, and only one place should decide availability | Needs both kinds of hardware |
| **Run after every full reset only** | Simple and predictable, and workers wait for it | A street that breaks later is only reported by timeouts until the next reset |
| **Start with everyone on the same tick** | No messages needed to coordinate. Each phase lasts 32 ticks, leaving plenty of margin | Depends on one clean reset, which an FPGA gives us |
| **Available means "your report really reached me"** | Tests the real path both ways, and no maths about routes is needed | A house is all or nothing |
| **Memory test left out** | Out of scope. Links are the question | A bad memory cell isn't caught |
| **Start every test bit at "failed"** | A missing answer can never look healthy | None worth noting |

### The move that made M3 strong

At first, a broken street simply got closed. When we counted honestly, one broken street left only 1 to 2 of 3 workers usable, and tile 0 was lost every time. The X-Y rule meant no way round.

| Option | Result | Verdict |
|---|---|---|
| Close only the one broken direction | Average 2.0 workers, worst case still 1 | Not enough |
| **Share a closed-road list and go the other way round the ring** | 3 of 3 for every single fault | **Chosen** |
| A special always-working wire to share the list | Instant and tiny | Rejected. If such a perfect wire existed, why not send data on it? It would weaken the claim |

**Accepted limits.** These are on purpose, not oversights:
- The gateway's own router is a single point of failure for warehouse jobs.
- Inside-the-router faults aren't tested yet (planned after the board tests).
- Two opposite broken streets split the town in two.
- Detours work on 2×2 only.

### Later decisions: privacy, recovery, and the comparison town

| Decision | Why | Cost |
|---|---|---|
| **Test the intersections too, not only the streets** | A cop who sends cars the wrong way is as bad as a broken street. Each cop is now tested from the inside every morning | The inspection takes longer (545 ticks, up from 329). The cop's stopwatch is still not tested |
| **A failed intersection is cut out completely** | We can't trust any of its exits, so all its streets go on the closed-road list | That house is lost. The other houses carry on |
| **An optional "read only my mailbox" rule** | Without it any worker could read another's private notes, including secret keys | It is off by default, because one test program reads its neighbours' code on purpose |
| **A secret stamp on messages, done by the programs** | Any house can write to any mailbox, so a message needs proof of who sent it | A worker who knows the secret can still forge. Hardware does not enforce it |
| **Let any house restart a collapsed worker** | Before, one stopped worker stayed stopped until the whole town was reset | Nothing checks who restarts whom |
| **No hardware lock on shared notes** | Keeps the mail room small, and programs can choose their own rules. The warehouse lock covers the big transfers | Two workers writing one shared note at once corrupt it silently. Programs must avoid this |
| **Build the one-road town with the same houses** | If only the roads differ, any difference we measure is the roads | It is not a textbook bus |
| **Measure the roads with pretend workers** | A real worker is so slow that both towns sit mostly idle, so they looked equal | The result is about the roads, and we say so |
| **A hash-based signature, not ML-DSA** | ML-DSA needs far more memory than a house has and is all multiplication, which these workers do slowly in software | A one-time signature: one key signs one message |

### What we take for granted

Every design rests on assumptions. Ours, in plain words:

- **Each worker sends one request at a time and waits.** The no-jam guarantee depends on this.
- **Everyone wakes at the same moment.** The inspectors keep in step by counting ticks, not by talking.
- **Things that are broken are broken at wake-up.** The inspection runs once. A street that breaks later is noticed (letters time out) but not driven round until the next reset.
- **Only streets and intersections break.** Workers, mail rooms and memories are trusted.
- **Programs behave.** One writer per shared note; give the warehouse key back.
- **Four houses.** Driving round a fault relies on the streets forming a ring.

If one of these stops being true, the matching guarantee goes with it. `docs/assumptions_decisions_risks.md` lists what fails and how.

## Part 2: The mistakes

Mistakes are the most useful part of this file. The lesson matters more than the slip.

### Design bugs that were found and fixed

| Mistake | What went wrong | Lesson |
|---|---|---|
| **Letters could mix** | The router tracked which exit each entrance used, but didn't reserve the exit. A second letter could cut in, causing a permanent jam | Reproduce a bug in simulation first. It proves you've fixed the right thing |
| **"Ready" chained round the town** | Each street's "I have room" signal depended on the next one's, forming a loop | Break long signal chains with a register |
| **Two-way wait** | A mail room refused new letters until its own reply went out, while the reply was waiting on others | Replies must never depend on new requests |
| **"Timeouts aren't needed"** | Early reasoning covered a sender quitting midway, not a reply that never comes. That second case is what this project is about | Check an assumption against your actual goal |
| **Mail rooms joined the wrong port** | All four drove the west port instead of the local one, and all four had the same ID | Hand-wiring invites this kind of slip. It's why the town is now generated by code |
| **House numbers crossed** | Numbering used the X and Y axes the other way from the address map | One numbering, used everywhere |
| **A file that never compiled** | `ni.v` contained a pasted module declaration, and `make test` was broken after includes were commented out for Vivado | Run the tests constantly, so a break can't sit unseen |

### Slips during the BIST build

| Mistake | What happened | Lesson |
|---|---|---|
| **The test was wrong, not the hardware** | Three BIST checks failed. The hardware was right. Our expected values forgot a known limit: a broken street also hides its healthy reverse | When a test fails, check the expectation as well as the design |
| **Reserved words** | We named signals `local` and `expect`, and later `use`. All are reserved keywords | Small and quick to fix, but a name check would catch them sooner |
| **Lease test too short** | A 400-tick lease expired between 1024-tick retries, so a worker lost its key while still trying | Timers have to agree with each other. Now noted in a comment |
| **Unconnected inputs** | New ports left open in one testbench read as unknown (X) and broke it | Every new port means updating every user of that part |
| **Pretend forklift ran off its memory** | Zone addresses were larger than the model's memory, so it now wraps around | Test helpers have bugs too |
| **Accidental latch** | A loop counter wasn't set on every path, so synthesis added stray memory. `make synth_check` caught it | Simulation won't show everything, so also run the hardware checks |
| **Used before declared** | `bist_fault` in the board top was used above its declaration. Icarus accepted it, but Vivado can reject it | One tool passing doesn't mean all will |

### Slips during the benchmark and demo work

| Mistake | What happened | Lesson |
|---|---|---|
| **A "pass" that checked nothing** | A build setting renamed the benchmark's `main`, and also renamed the call in our start-up file, so our result check was skipped. Dhrystone "passed" unchecked | A pass only counts if you have seen the check fail at least once |
| **The benchmark ignored our setting** | Dhrystone's own header fixes 500 runs and silently overrode ours. Our timing was for the wrong count | Read what the borrowed code really does |
| **Old switch numbers left behind** | After the fault switches moved (three switches on our board are faulty), the regression still drove the old value. It injected no fault and nobody noticed | When hardware mapping changes, search for every use |
| **The new test broke an old feature** | The intersection test ran while a debug setting had one exit switched off. The cop "failed" and was cut out of the town | A new check must not judge things that were switched off on purpose |
| **Workers started before the warehouse was ready** | On the board the big memory needs time to calibrate. Cores started earlier. Simulation could not show it, because the pretend warehouse is always ready | Ask what the model leaves out |
| **A test that looked stuck** | The random-traffic test seemed to hang. It was just slow, and its output was buffered | Measure before concluding |
| **Unknown is not zero** | The scorekeeper expected 0 in never-written slots; the simulator says "unknown". 61 false failures, the same on both towns | A failure that is identical everywhere is probably the test |

### Wrong claims, the kind to watch most

These cost nothing to fix, but they would have misled people.

| Claim | Truth | Lesson |
|---|---|---|
| **The README said M3 was "at least 2 workers"** | Counting every case gave a worst case of 1. Counting properly is what led to the detour | Measure a headline number before stating it |
| **"Flip SW15 while running to see timeouts"** | The test program finishes within a millisecond, so no traffic is left to notice. Nothing would show | Think through what the board will really do, not only the logic |
| **"These benchmarks compare the two towns"** | The processor tests and speed tests run inside one house and never use the streets, so they are bound to be equal. They show the workers work, nothing more | Know what a test can and can't tell you |
| **"Duplicate assign in `mesh_top`"** | No such thing. Two overlapping printouts showed one line twice | Check a finding before reporting it, and retract openly when it's wrong |

### Tool surprises

- `timeout` doesn't exist on macOS, so a Yosys run silently did nothing the first time.
- A Yosys path-length tool reported thousands of "loops" because it didn't recognise Xilinx flip-flops. They were false, and the design's real loop check is clean.
- The logic-depth estimate never finished. Vivado's timing report will answer that question properly.

## The pattern

Most of the bugs came from one of three habits: wiring by hand, assuming instead of measuring, and trusting a single tool. The project's answers are generated wiring, sweeping every case instead of a chosen few, and checking with several tools. Deliberately breaking the design confirms that the tests can fail.
