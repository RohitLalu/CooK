// model_test.h -- riscv-arch-test target macros for a CooK tile (NoC or
// single bus). A test ends by writing the pass word to the tile's status CSR;
// the testbench then dumps the memory between begin_signature and
// end_signature, which run_arch_test.py compares with Spike's.
// TILE_BASE comes from the build.
#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

#define RVMODEL_HALT                                        \
        li   t0, TILE_BASE;                                 \
        li   t1, 0x600D0000;                                \
        sw   t1, 8(t0);                                     \
1:      j    1b;

#define RVMODEL_BOOT
#define RVMODEL_DATA_BEGIN  .align 4; .global begin_signature; begin_signature:
#define RVMODEL_DATA_END    .align 4; .global end_signature; end_signature:

#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#endif
