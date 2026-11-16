# Assumptions, decisions, risks and failure modes

> **Status: COMPLETE** (2026-11-16). The document is finished. Its section 4 lists future work, which is open by definition.

What the design takes for granted, what was decided because of it, what each
decision costs, and how the system behaves when firmware is wrong or hardware
breaks while running. Future work is at the end. Status of each feature (built,
simulated, on the board) is in `docs/known_issues.md` and the README.

## 1. Assumptions

| # | Assumption | Where the design depends on it |
|---|---|---|
| A1 | **Each core has at most one remote read outstanding.** PicoRV32 issues one memory access at a time and waits for it. | Request/response deadlock safety; the NI's response queue is sized for it. |
| A2 | **One clock, one reset, everything leaves reset on the same edge.** | The BIST nodes run a fixed schedule in step without talking to each other first. |
| A3 | **Faults are permanent and are there at start-up.** A link is dead or alive; a router works or does not. | BIST runs once after reset; the dead-link list never changes afterwards. |
| A4 | **Faults are in links and routers.** The cores, the network interfaces, the block RAMs, the clock and the BIST logic itself are taken to work. | Nothing tests them. The local wire between a router and its NI is also trusted. |
| A5 | **Firmware cooperates.** Programs follow the mailbox protocol, keep one writer per shared word, and release the DMA lock. | There is little hardware enforcement beyond the write window, the optional read window and the DMA checks. |
| A6 | **The mesh is 2×2.** | Routing around a dead link or a failed router uses the fact that four links form a ring. |
| A7 | **Power and the USB link are stable.** No reset or brown-out in the middle of a DMA transfer. | A DMA transfer under the lock is treated as one unit that always finishes. |
| A8 | **Packets are two flits and a tile is at most 1 MB.** | Header layout; buffer sizes; whole-packet admission. |
| A9 | **The key material in the demos is compiled in on both sides.** | The crypto demo, the mailbox checksum, the laptop link. Not a key exchange. |

## 2. Decisions that follow

| Decision | Because of | What it buys | What it costs |
|---|---|---|---|
| Deterministic X-Y routing, no virtual channels | A1, small scale | Cannot deadlock by construction; small routers | One path per pair in normal operation |
| Storage in link FIFOs, not in routers; a packet is admitted only when it fits whole | A8 | A stalled output means a fault, not congestion, so a watchdog can tell them apart | FIFO memory on every link |
| Check bits on every flit, poison TAIL, watchdog, NI timeout and retry | A3 is not fully true: things do go wrong while running | A core never hangs on a lost packet; it gets `POISON` and a flag | Posted writes cannot be retried |
| BIST once after reset: link ping-pong, then router self-test, then a shared dead-link list | A2, A3 | A broken link or router is found and named before any core runs | A fault that appears later is not routed around |
| Route around a dead link or failed router by going the other way round the ring | A6 | Any single link fault costs no core; a failed router costs only its own tile | Works on 2×2 only |
| Availability decided at the gateway by actually reading each tile | A4 | No path arithmetic; a wrong "healthy" is impossible | The gateway is a single point of failure for DDR and availability |
| DMA lock with turn-taking and a lease; zones in the DDR; checks at the "go" write | A5 is not trusted for DDR | A buggy or dead core cannot hold or overrun the DDR | A fixed zone split; a lease length chosen by judgement |
| **No atomic operation between cores in hardware; mutual exclusion on shared words is firmware's job** | A5, A7 | A small NI; policy can change without a new bitstream | Nothing stops two cores racing on a shared word |
| Remote write window (mailbox only), optional remote read window | A5 partly distrusted | A neighbour cannot overwrite a program, or read its private data | Reads are open unless the option is on, because `alltoall.S` needs them |
| Mailbox sender check as a keyed checksum in firmware | A5, A9 | A core without the key cannot forge a job; damaged messages are caught | A program with the key still can; 32-bit tag |
| Per-tile restart through a register any tile can write | A4 is not fully true: a core can trap | A stopped core can be started again without a full reset | No check on who restarts whom; code is not reloaded |
| No caches | Each core has its own single-cycle block RAM | No coherence problem exists | Not a shared-memory multiprocessor in the usual sense |
| Reuse the same NI and software on the single-bus baseline | Fair comparison | Any measured difference is the interconnect | The baseline is not a textbook AXI bus |

## 3. How it fails

### If firmware is written wrongly

| Mistake | What happens | Caught by hardware? |
|---|---|---|
| Two cores write the same shared word or mailbox slot | The last write wins; data is corrupted silently | **No.** This is the price of the atomic-operations decision |
| A core writes outside another tile's mailbox | The write is dropped and the target's illegal flag is set | Yes |
| A core reads another tile's private memory | With the read window on: `POISON` and a flag. With it off: the read succeeds | Only with the option on |
| A core forges a mailbox message | Ignored if it lacks the key. Accepted if it has the key | Firmware only |
| A core takes the DMA lock and never releases it | The lease expires and the next core gets the lock; a flag is set | Yes |
| A core programs the DMA wrongly (other tile, wrong zone, bad length) | The request is refused with a reason code; nothing moves | Yes |
| A core uses an address that is no tile's | `POISON`, illegal flag, no hang | Yes |
| A program ignores `POISON` or the error flags | It computes with `0xDEADBEEF` as if it were data | No. Firmware must check |
| A program overruns its stack into its own data or mailbox | Silent corruption inside that tile | No. There is no memory protection inside a tile |
| A core executes garbage and traps | It stops; its trap flag is readable by others, who may restart it | Detected; recovery is firmware's choice |
| A core restarts another core that was working | That core's work is lost | No |
| A core jumps into another tile's memory | With the read window off it runs that code (remote fetch). With it on it reads `POISON` and traps | Only with the option on |

### If a link or router breaks while the system is running

BIST has already finished, so nothing reroutes. What protects the system is
detection, not repair.

| Break | What happens | What the cores see |
|---|---|---|
| A link goes silent | Packets for it queue; the router's watchdog marks that output dead and drops what waits for it | Reads across it time out after three tries and return `POISON`; the timeout flag is set. Cores that do not use the link carry on |
| A link flips bits | Check bits fail at the next router or NI; the packet is dropped or cut short with a poison TAIL | The same: retry, then `POISON` |
| A posted write is lost on that link | Nothing reports it to the sender | **Nothing, unless firmware reads back or uses the mailbox checksum** |
| A router fails inside | Its outputs misbehave; neighbours see bad check bits or stalled outputs | Timeouts and `POISON` for everything through that router |
| The gateway's router or link fails | DDR and DMA are unreachable for everyone | DMA requests time out; the lock's lease frees it |
| A fault during a DMA transfer | Words that were in flight are lost; the gateway's flags record an error where it can tell | A partly written block. Firmware must verify what it moved |
| A core's own NI or RAM fails | Outside the fault model | Undefined |

In every row but the last, the system as a whole does not hang: each affected
access ends, with an error. A full reset then reruns BIST, which finds the
fault and routes around it if it can. The simulated evidence: the mesh test
with a link broken after BIST, and the looping-traffic demo with a link killed
mid-run.

### Risks accepted with these decisions

1. **Silent data corruption from a firmware race** on shared words (A5).
2. **Silent loss of a posted write** after a run-time fault.
3. **A hang, not an error, if assumption A1 is broken** by a future core or NI that issues several reads at once. Nothing checks A1.
4. **One point of failure**: the gateway.
5. **No recovery without a reset** from a fault that appears after start-up.
6. **Start skew**: a board where the nodes do not leave reset together could give false BIST results (A2).
7. **The untested parts**: NIs, RAMs, BIST logic, and the router's watchdog and drop paths.

## 4. Future work

| Topic | What it would add | What it has to solve first |
|---|---|---|
| **Fixing the current known limitations** | The open items in `docs/known_issues.md`: rerouting beyond 2×2, separate request and response channels, routing around faults that appear at run time, a second path to memory, the untested router paths, hardware enforcement of the mailbox sender | Each is listed there with a suggested fix; several overlap with the rows below |
| **Formal verification** | A proof, in place of testing, of the properties now only argued or soak-tested: no deadlock under A1, no packet loss or duplication in a healthy fabric, router lock exclusivity, lock and lease safety at the gateway | Writing the properties and environment assumptions; the router and link FIFO are small enough to start with |
| **Caches, coherence and consistency** (the step to true multiprocessing) | Cores sharing memory through private caches, with a protocol that keeps the copies consistent: MESI states, and a snooping or directory scheme to carry the messages | A mesh has no shared wire to snoop, so plain snooping does not fit; a directory protocol over the NoC, or snooping over an ordered broadcast, has to be chosen. It also ends assumption A1 and needs separate request and response channels |
| **Dynamic X-Y routing; buffers in the router** | Routing that reacts to congestion or to faults found at run time; a comparison of input-buffered routers against the present storage-free crossbar with link FIFOs | Adaptive routing reopens deadlock (turn models or virtual channels) and packet ordering. The comparison needs area, timing and throughput for both styles under the same traffic |
| **In-order and out-of-order cores** | Cores fast enough to load the interconnect, so that CPU benchmarks show the fabric's effect | An out-of-order core issues several memory accesses at once: again the end of A1 |
| **3×3 and larger** | Scaling results on real cores; more faults survivable | Deadlock-free rerouting beyond the 2×2 ring (up\*/down\* tables from the dead-link list); BIST gossip time grows with size |
| **A second memory element** | No single point of failure for memory; traffic to two memories on separate paths | A second gateway, lock and zone ownership across two gateways, and where availability is decided |
| ML-based verification | Optional; not planned now | |

Three of these (caches, out-of-order cores, larger meshes) remove assumption
A1. Separate request and response channels are therefore the common
prerequisite, and formal verification of the deadlock property is worth doing
before any of them.
