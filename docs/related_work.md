# Related work: fault-tolerant networks-on-chip

> **Status: OPEN** (2026-11-22). A first pass from about a dozen web searches,
> reading abstracts and index pages only. It is enough to position the work,
> not enough for a "to our knowledge" claim in a paper. Next: search IEEE
> Xplore and Google Scholar properly, starting from the reference list of the
> Werner et al. survey, and read the full text of the papers below.

## Conclusion first

**The network-level parts of CooK are not new.** A NoC that runs a built-in
self-test and then reconfigures its routing around what failed is a
well-studied area (Vicis, Ariadne, uDIREC, LBDR and others below), and those
designs do it at larger scale and more generally than CooK's 2×2 ring detour.
Using self-test results to decide which tiles get work is also established,
in software resource managers and fault-aware task mapping (Kerkhoff et al.,
FARM).

**What the search did not find:**
- an availability map, derived from the network's own self-test, enforced
  **in hardware at the memory-access boundary**, so that an unreachable tile
  cannot take part in a DMA transfer;
- an **open FPGA prototype** that combines NoC self-test, routing around
  faults, RISC-V cores, board-level fault injection, and a comparison against
  a bus built from the same parts.

Absence in a short web search is not proof.

## The claim that survives

> A self-test-derived availability map enforced in hardware at the
> memory-access boundary, so an unreachable tile cannot take part in DMA,
> shown on an open FPGA prototype with RISC-V cores, board-level fault
> injection, and a comparison against a bus built from the same parts.

The link test, router self-test and rerouting are then described as standard
techniques, implemented at small scale, and cited to the work below.

## The papers

| Work | What it does | Overlap with CooK |
|---|---|---|
| **Vicis** (Fick et al., DAC 2009) | Each router runs BIST to locate hard faults; a distributed algorithm reconfigures the network. Also port swapping, ECC, crossbar bypass. Keeps working with about half its routers failed | Link test, router self-test, routing around faults |
| **Fick et al., DATE 2009**, "A highly resilient routing algorithm for fault-tolerant NoCs" | Distributed routing algorithm that reconfigures a deterministically routed NoC to avoid faulty components while keeping connectivity | Routing around dead links |
| **Ariadne** (Aisopos, DeOrio, Peh, Bertacco, PACT 2011) | Distributed reconfiguration with up\*/down\* routing for large unreliable NoCs; 64 nodes, 50 faults | The general form of CooK's 2×2 ring detour |
| **Hermes** | Adapts the up\*/down\* reconfiguration of Ariadne to 2D meshes | Mesh rerouting |
| **uDIREC** (Parikh, Bertacco, MICRO 2013; journal version IEEE TC 2016) | Fine-grained diagnosis that disables faulty components sparingly, plus deadlock-free reconfiguration; any topology; under 3 % area | Diagnosis and rerouting, done more finely and at scale |
| **BulletProof** (Constantinides et al., HPCA 2006) | Defect-tolerant router switch: reliability against area across designs; port swapping, crossbar bypass, ECC | Router-internal fault tolerance |
| **LBDR / uLBDR** (Flich, Duato and others) | Logic-based distributed routing configured by connectivity and routing bits; uLBDR gives full coverage of faulty 2D meshes | Mesh routing reconfigured from a fault map |
| **Grecu, Pande, Ivanov, Saleh** (VTS 2006; TCAD 2007) | BIST for inter-switch links, fault model including crosstalk; test methodology for NoC fabrics | CooK's link test (cited in the report as [2]) |
| **Strano et al.** (DATE 2011) | A complete BIST strategy for NoC testing | Link and router self-test |
| **Non-blocking NoC testing** (KTH) | Reconfigurable router with bypass channels, so cores stay connected while routers are under BIST | Testing at run time, which CooK does not do |
| **Online path-based NoC test** (UESTC, KTH) | Tests idle NoC components online after each application mapping; notes that link-only tests miss router control logic | Run-time testing; the router-logic gap |
| **Multi-layer diagnosis** (Schley et al., IEEE TC 2017; Wunderlich group, NOCS 2015) | Combines diagnosis across network layers for fault-tolerant NoCs | Diagnosis |
| **ter Braak, Kerkhoff et al.** (Int. Symp. System-on-Chip 2010) | A "Dependability Manager" self-tests processing tiles periodically; faulty tiles are excluded and replaced by spares through on-line resource management; the NoC is the test access path; verified on FPGA | **The closest to CooK's contribution**: a self-test result deciding which tiles are used. It acts on tiles through software resource management; CooK acts on the network and gates DMA in hardware |
| **FARM** (Chou, Marculescu, DATE 2011), fault-aware task mapping (TU Dresden and others) | Run-time resource management and task mapping that avoid faulty parts of an MPSoC | Availability used for allocation, in software |
| **Werner, Navaridas, Luján**, ACM Computing Surveys 2016 | Survey of design approaches that circumvent permanent faults in NoCs: topology, routing, router microarchitecture, system level, reconfiguration | The reading list to work through first |
| **Holistic fault-tolerant NoC many-core** (arXiv 1601.07089) | System view of fault tolerance in NoC-based many-cores | Background |
| **RISC-V fault tolerance on FPGA** (Wilson, Wirthlin et al., 2021–2022) | TMR and fault injection of open RISC-V soft cores, PicoRV32 among them, on SRAM FPGAs | Protects the cores, not the network; shows the gap on the network side |

## How CooK should cite and contrast

- Link test and router self-test: Grecu et al., Strano et al., Vicis.
  CooK's version is simpler (raw vectors through the link FIFO, one pass at
  start-up) and makes no claim beyond them.
- Routing around faults: Fick et al., Ariadne, uDIREC, LBDR. CooK's ring
  detour is a special case of up\*/down\* on a 2×2 mesh; general rerouting is
  future work.
- Using availability: Kerkhoff et al. and FARM use it to place work, in
  software. CooK uses it to admit or refuse DMA transfers, in hardware, at the
  boundary to memory.
- Evaluation: those papers report results at 64 nodes and above, mostly in
  simulation. CooK is a 2×2 FPGA prototype with measurements on the board and
  a bus baseline; it should say so and not compete on scale.

## Searches still to do

- IEEE Xplore and Google Scholar: "NoC BIST availability DMA", "fault-aware
  memory access NoC", "self-test gated memory controller", "NoC FPGA
  prototype fault injection".
- Citations of Shashank V's thesis and of Kerkhoff et al. 2010.
- The full text of the Werner et al. survey, section on system-level
  approaches.

## Sources

- [Vicis: a reliable network for unreliable silicon (DAC 2009)](https://researchr.org/publication/FickDHBBS09)
- [Fick et al., A highly resilient routing algorithm for fault-tolerant NoCs (DATE 2009)](https://past.date-conference.com/proceedings-archive/2009/DATE09/PDFFILES/02.2_4.PDF)
- [Ariadne (PACT 2011)](https://vufind-test.katalog.k.utb.cz/SummonRecord/FETCH-LOGICAL-i90t-4436a89da1d88f69d25954d1454ffad4febbb3d2c38ce485d32f8eac773510bc3)
- [Hermes](https://cosior.github.io/papers/hermes-1.pdf)
- [uDIREC (MICRO 2013)](https://microarch.org/micro46/files/paper2b3.html), [journal version (IEEE TC)](https://web.eecs.umich.edu/~valeria/research/publications/udirec_TC.pdf)
- [BulletProof (HPCA 2006)](https://vufind-test.katalog.k.utb.cz/SummonRecord/FETCH-LOGICAL-i241t-327c9ab85e19fdccbe1fc01ca304bb5ba29b636fc58f0ff7c6cf0b6bc78042be3)
- [LBDR-based fault-tolerant routing (NOCS 2012)](https://www.dcs.gla.ac.uk/~josecr/pub/2012_nocs.pdf)
- [Grecu et al., BIST for NoC interconnect infrastructures (VTS 2006)](https://search.isc.ac/Inventory/49/1630187.htm)
- [Strano et al., NoC BIST strategy (DATE 2011)](https://past.date-conference.com/proceedings-archive/2011/DATE11/PDFFILES/06.4_1.PDF)
- [Non-blocking testing for NoC](https://people.kth.se/~mebr/assets/files/y-%20Non-Blocking%20Testing%20for%20Network-on-Chip.pdf)
- [Online path-based test method for NoC](https://people.kth.se/~mebr/assets/files/y-%20Online%20Path-Based%20Test%20Method%20for%20Network-on-Chip.pdf)
- [Multi-layer diagnosis for fault-tolerant NoCs (IEEE TC 2017)](https://www.iti.uni-stuttgart.de/fileadmin/rami/files/publications/2017/TC_SchleDEHWR2017.pdf)
- [ter Braak, Kerkhoff et al., On-line dependability enhancement of MPSoCs by resource management (SoC 2010)](https://ris.utwente.nl/ws/files/5459706/SoC_2010.pdf)
- [Kerkhoff and Zhang, Dependability Manager design](https://ris.utwente.nl/ws/files/283523880/Kerkhoff2010design.pdf)
- [Werner, Navaridas, Luján survey (ACM CSUR 2016)](https://apt.cs.manchester.ac.uk/publications/papers/SW_CSUR16.php)
- [Holistic approach for fault-tolerant NoC-based many-core systems](https://www.arxiv.org/pdf/1601.07089)
- [Fault injection of TMR open-source RISC-V processors on SRAM FPGAs](https://par.nsf.gov/servlets/purl/10345470)
- [Euromicro DSD 2026 call for papers](https://easychair.org/cfp/DSD2026)
