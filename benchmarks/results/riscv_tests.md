# riscv-tests rv32ui on both architectures

Three cores run each test at the same time, from their own tile memory.
Tile memory 64 KB (`NOC_OFFSET_BITS=16`). Cycles from core reset release
until all three cores report. Interconnect flits: flits entering the mesh, or
bus-busy cycles.

| Test | Words | NoC | NoC cycles | NoC flits | Bus | Bus cycles | Bus busy |
|---|---|---|---|---|---|---|---|
| add | 323 | pass | 2216 | 0 | pass | 2217 | 0 |
| addi | 173 | pass | 1065 | 0 | pass | 1066 | 0 |
| and | 313 | pass | 2316 | 0 | pass | 2317 | 0 |
| andi | 123 | pass | 845 | 0 | pass | 846 | 0 |
| auipc | 28 | pass | 121 | 0 | pass | 122 | 0 |
| beq | 187 | pass | 1390 | 0 | pass | 1391 | 0 |
| bge | 211 | pass | 1516 | 0 | pass | 1517 | 0 |
| bgeu | 224 | pass | 1641 | 0 | pass | 1642 | 0 |
| blt | 187 | pass | 1390 | 0 | pass | 1391 | 0 |
| bltu | 200 | pass | 1515 | 0 | pass | 1516 | 0 |
| bne | 188 | pass | 1398 | 0 | pass | 1399 | 0 |
| fence_i | 64 | pass | 1749 | 0 | pass | 1750 | 0 |
| jal | 32 | pass | 106 | 0 | pass | 107 | 0 |
| jalr | 72 | pass | 445 | 0 | pass | 446 | 0 |
| lb | 152 | pass | 1216 | 0 | pass | 1217 | 0 |
| lbu | 152 | pass | 1216 | 0 | pass | 1217 | 0 |
| ld_st | 956 | pass | 5997 | 0 | pass | 5998 | 0 |
| lh | 164 | pass | 1296 | 0 | pass | 1297 | 0 |
| lhu | 172 | pass | 1341 | 0 | pass | 1342 | 0 |
| lui | 35 | pass | 164 | 0 | pass | 165 | 0 |
| lw | 176 | pass | 1366 | 0 | pass | 1367 | 0 |
| ma_data | 448 | TRAP | 37 | 0 | TRAP | 38 | 0 |
| or | 316 | pass | 2331 | 0 | pass | 2332 | 0 |
| ori | 130 | pass | 880 | 0 | pass | 881 | 0 |
| sb | 276 | pass | 2390 | 0 | pass | 2391 | 0 |
| sh | 316 | pass | 2655 | 0 | pass | 2656 | 0 |
| simple | 6 | pass | 32 | 0 | pass | 33 | 0 |
| sll | 351 | pass | 2585 | 0 | pass | 2586 | 0 |
| slli | 172 | pass | 1188 | 0 | pass | 1189 | 0 |
| slt | 317 | pass | 2186 | 0 | pass | 2187 | 0 |
| slti | 168 | pass | 1040 | 0 | pass | 1041 | 0 |
| sltiu | 168 | pass | 1040 | 0 | pass | 1041 | 0 |
| sltu | 317 | pass | 2186 | 0 | pass | 2187 | 0 |
| sra | 370 | pass | 2690 | 0 | pass | 2691 | 0 |
| srai | 185 | pass | 1253 | 0 | pass | 1254 | 0 |
| srl | 364 | pass | 2660 | 0 | pass | 2661 | 0 |
| srli | 179 | pass | 1223 | 0 | pass | 1224 | 0 |
| st_ld | 476 | pass | 2589 | 0 | pass | 2590 | 0 |
| sub | 315 | pass | 2176 | 0 | pass | 2177 | 0 |
| sw | 324 | pass | 2687 | 0 | pass | 2688 | 0 |
| xor | 315 | pass | 2326 | 0 | pass | 2327 | 0 |
| xori | 132 | pass | 890 | 0 | pass | 891 | 0 |

Passed: NoC 41 of 42, bus 41 of 42.
