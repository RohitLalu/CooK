# riscv-arch-test, RV32I base set, both architectures against Spike

Release 3.9.1, tile memory 64 KB. Reference signatures from Spike
(`--isa=rv32i`). A test passes when the signature read from the tile equals Spike's.

| Test | Signature words | NoC | NoC cycles | Bus | Bus cycles |
|---|---|---|---|---|---|
| add-01 | 592 | pass | 18340 | pass | 18341 |
| addi-01 | 564 | pass | 12894 | pass | 12895 |
| and-01 | 588 | pass | 18153 | pass | 18154 |
| andi-01 | 564 | pass | 12917 | pass | 12918 |
| auipc-01 | 68 | pass | 2608 | pass | 2609 |
| beq-01 | - | skipped: does not fit in a tile | - | skipped | - |
| bge-01 | - | skipped: does not fit in a tile | - | skipped | - |
| bgeu-01 | - | skipped: does not fit in a tile | - | skipped | - |
| blt-01 | - | skipped: does not fit in a tile | - | skipped | - |
| bltu-01 | - | skipped: does not fit in a tile | - | skipped | - |
| bne-01 | - | skipped: does not fit in a tile | - | skipped | - |
| fence-01 | 4 | pass | 836 | pass | 837 |
| jal-01 | - | skipped: does not fit in a tile | - | skipped | - |
| jalr-01 | 36 | pass | 5654 | pass | 5655 |
| lb-align-01 | 36 | pass | 3632 | pass | 3633 |
| lbu-align-01 | 36 | pass | 3545 | pass | 3546 |
| lh-align-01 | 36 | pass | 3545 | pass | 3546 |
| lhu-align-01 | 36 | pass | 3545 | pass | 3546 |
| lui-01 | 68 | pass | 1630 | pass | 1631 |
| lw-align-01 | 36 | pass | 3545 | pass | 3546 |
| misalign1-jalr-01 | 4 | pass | 902 | pass | 903 |
| or-01 | 592 | pass | 18332 | pass | 18333 |
| ori-01 | 564 | pass | 12841 | pass | 12842 |
| sb-align-01 | 72 | pass | 3581 | pass | 3582 |
| sh-align-01 | 76 | pass | 3604 | pass | 3605 |
| sll-01 | 92 | pass | 3374 | pass | 3375 |
| slli-01 | 92 | pass | 2897 | pass | 2898 |
| slt-01 | 588 | pass | 18258 | pass | 18259 |
| slti-01 | 564 | pass | 12856 | pass | 12857 |
| sltiu-01 | 704 | pass | 15693 | pass | 15694 |
| sltu-01 | 724 | pass | 22062 | pass | 22063 |
| sra-01 | 92 | pass | 3357 | pass | 3358 |
| srai-01 | 92 | pass | 2849 | pass | 2850 |
| srl-01 | 96 | pass | 3535 | pass | 3536 |
| srli-01 | 92 | pass | 2950 | pass | 2951 |
| sub-01 | 596 | pass | 18407 | pass | 18408 |
| sw-align-01 | 72 | pass | 3490 | pass | 3491 |
| xor-01 | 592 | pass | 18315 | pass | 18316 |
| xori-01 | 568 | pass | 12979 | pass | 12980 |

Passed: NoC 32 of 39, bus 32 of 39.
