/* libmin.c -- the few C library routines the programs need, so nothing is
 * linked from newlib. Multiplication and division come from libgcc (the
 * cores are RV32I: no M extension). */
#include "tile.h"

void *memcpy(void *d, const void *s, unsigned n)
{
    char *a = d; const char *b = s;
    while (n--) *a++ = *b++;
    return d;
}
void *memset(void *d, int c, unsigned n)
{
    char *a = d;
    while (n--) *a++ = (char)c;
    return d;
}
int memcmp(const void *a, const void *b, unsigned n)
{
    const unsigned char *x = a, *y = b;
    for (; n--; x++, y++) if (*x != *y) return *x - *y;
    return 0;
}
char *strcpy(char *d, const char *s)
{
    char *r = d;
    while ((*d++ = *s++)) ;
    return r;
}
int strcmp(const char *a, const char *b)
{
    while (*a && *a == *b) { a++; b++; }
    return (unsigned char)*a - (unsigned char)*b;
}
