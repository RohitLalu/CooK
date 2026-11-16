# User guide: finding your way around CooK

> **Status: COMPLETE** (2026-11-16). Paths and commands match the repository as of this date.

A map of the project for someone opening it for the first time. It says
where each thing lives, what to read first, and which command runs what. The
town picture used in the other `quick_look` files applies here too: houses
are tiles, workers are processor cores, streets are links, traffic cops are
routers.

## Start here

Read these three, in order. Each takes ten minutes.

1. `quick_look/1_architecture_and_software.md`: what the system is.
2. `quick_look/2_decisions_and_mistakes.md`: why it is built this way.
3. `quick_look/3_testing_on_nexys4.md`: how to run it on the board.

Then use the table below to go wherever you need.

## The folders

| Folder | Think of it as | What is in it |
|---|---|---|
| `rtl/` | The town itself | The hardware design, in Verilog |
| `tb/` | The crash-test lab | Testbenches for the hardware |
| `sw/` | The first job lists | Small assembly programs for the workers |
| `single_bus/` | The one-road town | The comparison system, with its own tests |
| `benchmarks/` | The exam hall | Standard tests and speed tests, and the tools that run them |
| `encryption_code/` | The secret-message office | Encryption programs and the laptop link |
| `demo_tests/` | The showroom | Programs made to be shown on the board |
| `cook_vivado/` | The factory | The Vivado project that turns the design into a chip image |
| `docs/` | The filing cabinet | Checklists, known issues, design notes |
| `quick_look/` | The visitor centre | Plain-language guides, including this one |
| `reports_and_ppt/` | The office | The mid-sem and end-sem reports |
| `resources/` | The library | The thesis and paper this project builds on |

## 1. The design

Everything is under `rtl/`. Each file starts with a long comment that
explains it; read that before the code.

| To understand | Open |
|---|---|
| Sizes and the packet layout, defined once for everything | `rtl/include/noc_defs.vh` |
| How a traffic cop works | `rtl/router/noc_router.v` |
| A street and its waiting lane | `rtl/router/link_buffer.v` |
| The morning inspection of streets and cops | `rtl/router/bist_node.v` |
| A house's mail room | `rtl/network_interface/ni.v` |
| How the town is laid out | `rtl/integrated/mesh/noc_mesh.v`, `mesh_top.v` |
| The warehouse door, the forklift key, the rules | `rtl/dma_ddr/gw_ni.v` |
| The board: clock, LEDs, display, switches | `rtl/board/` |
| The worker (not written by us) | `rtl/core/picorv32.v` |
| The one-road town | `single_bus/rtl/` and `single_bus/README.md` |

## 2. Simulations and tests

You need Icarus Verilog (`iverilog`). All commands run from the top folder.

| Command | What it does | Time |
|---|---|---|
| `make test` | Every hardware test for the town, small to large | about 10 min |
| `make router`, `make bist`, `make ni`, `make mesh`, `make gateway`, `make board` | One group at a time | seconds each |
| `make m3` | Breaks every street in turn and counts the workers still usable | 2 min |
| `make soak` | Random letters from every house, checked by a scorekeeper | 3 min |
| `make synth_check` | Checks the design can become real hardware cleanly | seconds |
| `cd single_bus && make test` | The same for the one-road town | 5 min |

A test prints `PASS` or `FAIL` lines and a total. Any `FAIL` stops the run.
What each test proves is in the table at the end of
`quick_look/1_architecture_and_software.md`.

## 3. Benchmarks

Everything is in `benchmarks/`. Read `benchmarks/README.md` first: it lists
what to install (the RISC-V compiler, and the Spike simulator through
`sh benchmarks/tools/install_spike.sh`) and the three test suites to
download.

| Command | What it runs | Time |
|---|---|---|
| `python3 benchmarks/run_riscv_tests.py` | The standard instruction tests | 5 min |
| `python3 benchmarks/run_arch_test.py` | The compliance tests, compared with Spike | 5 min |
| `python3 benchmarks/run_c_benchmarks.py` | Dhrystone and CoreMark | over an hour |
| `python3 benchmarks/run_fabric.py` | **The town against the one road under heavy traffic** | 1 min |

Results land in `benchmarks/results/`. Start with `SUMMARY.md` there: it has
every number in one place and says what each one does and does not show.

One thing to remember: the first three run inside a single house and never
use the streets, so they give the same numbers for the town and the one-road
town. They show the workers are correct. Only the fourth, and `make soak`,
compare the two towns.

## 4. Encryption and the laptop link

Everything is in `encryption_code/`; its `README.md` is the map.

| Command | What it does | Time |
|---|---|---|
| `python3 encryption_code/run_crypto.py` | Three workers: one makes keys and gives out jobs, one encrypts, one signs. Run on both towns, healthy and with a fault | 40 min |
| `python3 encryption_code/run_link_sim.py` | The laptop link, with the test playing the laptop | 10 min |
| `python3 encryption_code/link/laptop.py --port ... show "HELLO"` | The real laptop side, for the board | instant |

Add `--board` to the first two to build the programs for the real board
without simulating.

## 5. Demos

`demo_tests/README.md` lists each demo, what you should see on the board, and
whether it has been simulated. Run them all in simulation with
`python3 demo_tests/run_demos.py`.

## 6. The board

| Step | Where |
|---|---|
| Plain-language walk-through | `quick_look/3_testing_on_nexys4.md` |
| Tick-box checklist with expected readings | `docs/hardware_test.md` |
| Build and program scripts | `cook_vivado/build.tcl`, `cook_vivado/program.tcl` |
| The one-road town's own project | `single_bus/vivado_proj/` |
| The board top for the live laptop demo only | `encryption_code/rtl/nexys4ddr_live_top.v` |
| What every error code on the display means | top of `rtl/board/status_panel.v` |

## 7. Limits, risks and what comes next

| Question | Open |
|---|---|
| What is known to be missing or unverified? | `docs/known_issues.md` |
| What does the design take for granted, and what breaks if that is wrong? | `docs/assumptions_decisions_risks.md` |
| What happens if a program is written wrongly, or a street breaks while running? | the same file, section 3 |
| What is planned next? | the same file, section 4 |
| How should the "no deadlock" result be worded? | `docs/known_issues.md`, near the end |

## 8. The reports

`reports_and_ppt/midsem/` has the mid-semester report.
`reports_and_ppt/endsem/latex/` has the end-semester report as LaTeX; build it
with `pdflatex` (twice) or upload it to Overleaf.

## If you only have five minutes

1. Read the first section of `quick_look/1_architecture_and_software.md`.
2. Open `benchmarks/results/SUMMARY.md` and read the first table.
3. Run `make bist` and `python3 benchmarks/run_fabric.py`: one shows the town
   finding its own faults, the other shows it beating the one road.
