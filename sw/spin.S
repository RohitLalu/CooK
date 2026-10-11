# spin.S -- non-orchestrator tiles. They serve remote requests purely in
# hardware (the NI responder), so the core itself has nothing to do.
.section .text
.globl _start
_start:
spin:
    j    spin
