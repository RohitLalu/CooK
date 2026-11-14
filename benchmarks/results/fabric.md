# Fabric benchmark: mesh against shared bus under load

Same endpoints on both fabrics; 448 words per flow; cycles from a flow's start
until its last word is in the destination memory. "Alone" = only that flow runs,
"together" = all three start on the same cycle. On the mesh the three flows share
no link.

| Flow | NoC alone | NoC together | NoC slowdown | Bus alone | Bus together | Bus slowdown |
|---|---|---|---|---|---|---|
| DMA: DDR to tile 0 RAM | 1807 | 1807 | 1.00x | 1805 | 2697 | 1.49x |
| W1: tile 1 writes tile 2's mailbox | 1796 | 1796 | 1.00x | 1795 | 2687 | 1.50x |
| W2: tile 2 writes tile 1's mailbox | 1797 | 1796 | 1.00x | 1796 | 2689 | 1.50x |

| | NoC | Bus |
|---|---|---|
| All three together, until the last one finishes | 1807 | 2697 |
| The same three one after another (sum of the alone times) | 5400 | 5396 |
| Gain from running them together | 2.99x | 2.00x |

Every word arrived and no error flag was set: yes.
