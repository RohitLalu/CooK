/* dhry_cook.c -- runs the unmodified Dhrystone 2.1 from riscv-tests on a
 * CooK tile and checks the final values the benchmark's own report lists
 * ("should be: ..."). The tile reports pass only if all of them are right. */
#include "tile.h"
#undef main        /* the build renames the benchmark's main, not this file's */

extern int  Int_Glob, Bool_Glob;
extern char Ch_1_Glob, Ch_2_Glob;
extern int  Arr_1_Glob[50], Arr_2_Glob[50][50];
int dhry_main(int argc, char **argv);

/* dhrystone.h fixes the run count at 500 (its NUMBER_OF_RUNS overrides -D) */
#define DHRY_RUNS 500

int  printf(const char *fmt, ...) { (void)fmt; return 0; }
long cook_time(void) { static long t; t += 100000000; return t; }

int main(void)
{
    dhry_main(0, 0);
    return !(Int_Glob == 5 && Bool_Glob == 1 && Ch_1_Glob == 'A' && Ch_2_Glob == 'B' &&
             Arr_1_Glob[8] == 7 && Arr_2_Glob[8][7] == DHRY_RUNS + 10);
}
