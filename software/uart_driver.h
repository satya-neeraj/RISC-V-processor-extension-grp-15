/* ===========================================================================
 * uart_driver.h  --  MMIO-based UART TX driver
 * =========================================================================== */
#ifndef UART_DRIVER_H
#define UART_DRIVER_H

#include <stdint.h>

#define UART_DATA_ADDR 0x10000000
#define UART_STAT_ADDR 0x10000004

/* Blocking putchar: waits for TX not busy, then writes byte. */
void uart_putc(char c);

/* Blocking puts (no newline added). */
void uart_puts(const char *s);

/* Print unsigned decimal. */
void uart_put_udec(uint32_t v);

/* Print signed decimal. */
void uart_put_dec(int32_t v);

/* Print 8-hex-digit value with "0x" prefix. */
void uart_put_hex(uint32_t v);

/* Print a Q16.16 signed fixed-point number as "X.XXXX". */
void uart_put_q16_16(int32_t q);

#endif
