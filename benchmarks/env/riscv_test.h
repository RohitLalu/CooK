// riscv_test.h -- CooK environment for riscv-tests (isa/). Replaces the
// suite's own env/: no machine-mode setup, no tohost. A test reports through
// the tile's software-status CSR (offset 0x008 of the tile it runs on), the
// same convention every CooK program uses:
//   pass  0x600D0000 | number of the last test case
//   fail  0xFA110000 | number of the failing test case
// TILE_BASE (the tile's window, from the build) locates that CSR.
#ifndef _ENV_COOK_H
#define _ENV_COOK_H

#define RVTEST_RV32U
#define RVTEST_RV64U
#define TESTNUM gp

#define RVTEST_CODE_BEGIN       \
        .section .text.init;    \
        .globl _start;          \
_start:                         \
        li   TESTNUM, 0;

#define RVTEST_CODE_END

#define COOK_REPORT(code)       \
        li   t0, TILE_BASE;     \
        li   t1, code;          \
        or   t1, t1, TESTNUM;   \
        sw   t1, 8(t0);         \
1:      j    1b;

#define RVTEST_PASS COOK_REPORT(0x600D0000)
#define RVTEST_FAIL COOK_REPORT(0xFA110000)

#define EXTRA_DATA
#define RVTEST_DATA_BEGIN  .align 4; .global begin_signature; begin_signature:
#define RVTEST_DATA_END    .align 4; .global end_signature; end_signature:

#endif
