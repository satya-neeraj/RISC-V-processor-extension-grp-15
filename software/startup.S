/* ===========================================================================
 * startup.S  --  Reset vector for riscv_nn_soc
 *
 * Reset vector = 0x00000000 (IMEM base).  The first word of IMEM is thus the
 * first instruction executed after rst_n deasserts.
 *
 * Responsibilities:
 *   1. Set the stack pointer to _stack_top
 *   2. Zero the .bss section
 *   3. Jump to main()
 *   4. Spin forever on return
 * =========================================================================== */

    .section .text.init, "ax"
    .globl _start
_start:
    /* Set up stack pointer to top of DMEM -- hex 0x0002FFFC */
    lui   sp, 0x30       /* sp = 0x00030000 */
    addi  sp, sp, -4     /* sp = 0x0002FFFC */

    /* Zero .bss:  for (p = _bss_start; p < _bss_end; p+=4) *p = 0; */
    la    t0, _bss_start
    la    t1, _bss_end
bss_loop:
    bge   t0, t1, bss_done
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     bss_loop
bss_done:

    /* Jump to C main() */
    jal   ra, main

    /* main should never return; if it does, park. */
hang:
    j     hang
