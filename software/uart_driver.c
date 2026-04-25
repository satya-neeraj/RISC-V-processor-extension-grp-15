/* ===========================================================================
 * uart_driver.c  --  MMIO-based UART TX driver for the RV32I NN SoC.
 *
 * Uses bare MMIO to the UART regs exposed by soc_top.v:
 *   UART_DATA_ADDR : write a byte to enqueue TX
 *   UART_STAT_ADDR : bit 0 = busy (read)
 *
 * ---------------------------------------------------------------------------
 * PURE RV32I -- NO LIBGCC DEPENDENCY
 * ---------------------------------------------------------------------------
 * RV32I has no hardware multiply/divide instructions.  Writing v / 10,
 * v % 10, or a * b in plain C would make GCC emit calls to libgcc helpers
 * (__udivsi3, __umodsi3, __mulsi3, ...) which we do not link.
 *
 * All multiply/divide in this file uses two tiny, self-contained helpers:
 *   - sw_mul32()  -- 32x32 -> 32 shift-and-add multiply (O(log b))
 *   - sw_divmod() -- 32/32 -> quotient + remainder restoring division (O(32))
 *
 * These are small enough that performance is not a concern for UART printing
 * (a few dozen multiplies/divides per message, vs. millions of cycles of MAC).
 * =========================================================================== */
#include "uart_driver.h"

static inline uint32_t mmio_rd(uint32_t addr) {
    return *((volatile uint32_t *)addr);
}
static inline void mmio_wr(uint32_t addr, uint32_t val) {
    *((volatile uint32_t *)addr) = val;
}

/* -------------------------------------------------------------------------
 * sw_mul32 -- unsigned 32x32 -> 32 shift-and-add multiply.
 * Skips zero bits in 'b' so worst case is 32 iterations; typical is far less.
 * ------------------------------------------------------------------------- */
static uint32_t sw_mul32(uint32_t a, uint32_t b) {
    uint32_t p = 0;
    while (b) {
        if (b & 1u) p += a;
        a <<= 1;
        b >>= 1;
    }
    return p;
}

/* -------------------------------------------------------------------------
 * sw_divmod -- unsigned 32/32 restoring division, 32 iterations.
 * Returns q = n / d, r = n - q*d via pointer.  If d == 0, returns q=0, r=n.
 * ------------------------------------------------------------------------- */
static void sw_divmod(uint32_t n, uint32_t d, uint32_t *q, uint32_t *r) {
    uint32_t quot = 0, rem = 0;
    if (d == 0) { *q = 0; *r = n; return; }
    for (int i = 31; i >= 0; i--) {
        rem = (rem << 1) | ((n >> i) & 1u);
        if (rem >= d) {
            rem  -= d;
            quot |= (1u << i);
        }
    }
    *q = quot;
    *r = rem;
}

/* ========================================================================= */

void uart_putc(char c) {
    while (mmio_rd(UART_STAT_ADDR) & 1u) { /* wait while TX busy */ }
    mmio_wr(UART_DATA_ADDR, (uint32_t)(unsigned char)c);
}

void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

void uart_put_udec(uint32_t v) {
    char buf[12];
    int  i = 0;
    uint32_t q, r;
    if (v == 0) { uart_putc('0'); return; }
    while (v) {
        sw_divmod(v, 10u, &q, &r);
        buf[i++] = (char)('0' + r);
        v = q;
    }
    while (i--) uart_putc(buf[i]);
}

void uart_put_dec(int32_t v) {
    if (v < 0) { uart_putc('-'); v = -v; }
    uart_put_udec((uint32_t)v);
}

void uart_put_hex(uint32_t v) {
    static const char hex[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int i = 7; i >= 0; i--) uart_putc(hex[(v >> (i << 2)) & 0xFu]);
}

/* Print a Q16.16 fixed-point number as "X.YYYY" (4 decimal places).
 *
 * The fractional decimal digits are computed via 'frac * 10000 / 65536',
 * i.e. '(frac_bin * 10000) >> 16'.  Both frac_bin and 10000 fit in 16 bits,
 * so the product fits in 32 bits.  We use sw_mul32 for the multiply (no
 * libgcc dependency). */
void uart_put_q16_16(int32_t q) {
    uint32_t ip, frac_bin;
    uint32_t prod, decimal_4;

    if (q < 0) { uart_putc('-'); q = -q; }
    ip       = ((uint32_t)q >> 16) & 0xFFFFu;
    frac_bin = ((uint32_t)q      ) & 0xFFFFu;

    uart_put_udec(ip);
    uart_putc('.');

    prod      = sw_mul32(frac_bin, 10000u);
    decimal_4 = prod >> 16;

    if (decimal_4 < 1000) uart_putc('0');
    if (decimal_4 <  100) uart_putc('0');
    if (decimal_4 <   10) uart_putc('0');
    uart_put_udec(decimal_4);
}
