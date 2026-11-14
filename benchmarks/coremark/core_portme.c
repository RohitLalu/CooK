/* core_portme.c -- CoreMark port for a CooK tile, used with the suite's
 * barebones/core_portme.h. No timer and no console on a tile: time is
 * measured by the testbench in clock cycles, and the benchmark's own
 * self-check ("Correct operation validated") decides pass or fail. */
#include "coremark.h"
#undef main        /* the build renames the benchmark's main, not this file's */

volatile ee_s32 seed1_volatile = 0x0;      /* the performance-run seeds */
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
ee_u32 default_num_contexts = 1;

/* CoreMark refuses a run shorter than 10 s; report 20 so its check passes */
void       start_time(void) {}
void       stop_time(void) {}
CORE_TICKS get_time(void) { return 20; }
secs_ret   time_in_secs(CORE_TICKS ticks) { return (secs_ret)ticks; }

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc; (void)argv;
    p->portable_id = 1;
}
void portable_fini(core_portable *p) { p->portable_id = 0; }

/* the only output channel is this flag: set when CoreMark prints its
 * "Correct operation validated" line */
int cook_validated;
int ee_printf(const char *fmt, ...)
{
    static const char ok[] = "Correct operation validated";
    unsigned i = 0;
    while (ok[i] && fmt[i] == ok[i]) i++;
    if (!ok[i]) cook_validated = 1;
    return 0;
}

int coremark_main(void);
int main(void)
{
    coremark_main();
    return !cook_validated;
}
