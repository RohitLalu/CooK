# riscv-arch-test, RV32I base set, both architectures against Spike

Release 3.9.1, tile memory 64 KB (1024 KB for the tests that need it). Reference signatures from Spike
(`--isa=rv32i`). A test passes when the signature read from the tile equals Spike's.

| Test | Tile KB | Signature words | NoC | NoC cycles | Bus | Bus cycles |
|---|---|---|---|---|---|---|
| add-01 | 64 | 592 | pass | 18340 | pass | 18341 |
| addi-01 | 64 | 564 | pass | 12894 | pass | 12895 |
| and-01 | 64 | 588 | pass | 18153 | pass | 18154 |
| andi-01 | 64 | 564 | pass | 12917 | pass | 12918 |
| auipc-01 | 64 | 68 | pass | 2608 | pass | 2609 |
| beq-01 | 1024 | 588 | pass | 29915 | pass | 29916 |
| bge-01 | 1024 | 592 | pass | 31349 | pass | 31350 |
| bgeu-01 | 1024 | 728 | pass | 38208 | pass | 38209 |
| blt-01 | 1024 | 584 | pass | 30737 | pass | 30738 |
| bltu-01 | 1024 | 728 | pass | 38072 | pass | 38073 |
| bne-01 | 1024 | 588 | pass | 32083 | pass | 32084 |
| fence-01 | 64 | 4 | pass | 836 | pass | 837 |
| jal-01 | - | - | skipped: larger than the biggest tile (1 MB) | - | skipped | - |
| jalr-01 | 64 | 36 | pass | 5654 | pass | 5655 |
| lb-align-01 | 64 | 36 | pass | 3632 | pass | 3633 |
| lbu-align-01 | 64 | 36 | pass | 3545 | pass | 3546 |
| lh-align-01 | 64 | 36 | pass | 3545 | pass | 3546 |
| lhu-align-01 | 64 | 36 | pass | 3545 | pass | 3546 |
| lui-01 | 64 | 68 | pass | 1630 | pass | 1631 |
| lw-align-01 | 64 | 36 | pass | 3545 | pass | 3546 |
| misalign1-jalr-01 | 64 | 4 | pass | 902 | pass | 903 |
| or-01 | 64 | 592 | pass | 18332 | pass | 18333 |
| ori-01 | 64 | 564 | pass | 12841 | pass | 12842 |
| sb-align-01 | 64 | 72 | pass | 3581 | pass | 3582 |
| sh-align-01 | 64 | 76 | pass | 3604 | pass | 3605 |
| sll-01 | 64 | 92 | pass | 3374 | pass | 3375 |
| slli-01 | 64 | 92 | pass | 2897 | pass | 2898 |
| slt-01 | 64 | 588 | pass | 18258 | pass | 18259 |
| slti-01 | 64 | 564 | pass | 12856 | pass | 12857 |
| sltiu-01 | 64 | 704 | pass | 15693 | pass | 15694 |
| sltu-01 | 64 | 724 | pass | 22062 | pass | 22063 |
| sra-01 | 64 | 92 | pass | 3357 | pass | 3358 |
| srai-01 | 64 | 92 | pass | 2849 | pass | 2850 |
| srl-01 | 64 | 96 | pass | 3535 | pass | 3536 |
| srli-01 | 64 | 92 | pass | 2950 | pass | 2951 |
| sub-01 | 64 | 596 | pass | 18407 | pass | 18408 |
| sw-align-01 | 64 | 72 | pass | 3490 | pass | 3491 |
| xor-01 | 64 | 592 | pass | 18315 | pass | 18316 |
| xori-01 | 64 | 568 | pass | 12979 | pass | 12980 |

Passed: NoC 38 of 39, bus 38 of 39.
