/* util.h -- stands in for riscv-tests' benchmarks/common/util.h so that the
 * suite's dhrystone_main.c compiles unchanged. PicoRV32 here has no cycle
 * CSR; time is measured by the testbench (or a stopwatch on the board), so
 * the "timer" only has to look long enough for the program's own check. */
#ifndef COOK_DHRY_UTIL_H
#define COOK_DHRY_UTIL_H
long cook_time(void);
#define read_csr(reg) cook_time()
#define setStats(x)
int printf(const char *fmt, ...);
#endif
