/* ===========================================================================
 * link.ld -- Linker script for riscv_nn_soc
 *
 * IMEM  : 0x0000_0000, 64 KB   (text + rodata)
 * DMEM  : 0x0001_0000, 128 KB  (data + bss + stack)
 *
 * Stack grows down from 0x0002_FFFC.
 * =========================================================================== */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rwx) : ORIGIN = 0x00010000, LENGTH = 128K
}

SECTIONS {
    /* ---------- Code ---------- */
    .text : {
        KEEP(*(.text.init))    /* startup first */
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > IMEM

    /* ---------- Initialized data (placed in DMEM) ---------- */
    .data : {
        . = ALIGN(4);
        _data_start = .;
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        _data_end = .;
    } > DMEM

    /* ---------- Uninitialized data ---------- */
    .bss : {
        . = ALIGN(4);
        _bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DMEM

    /* ---------- Stack ---------- */
    . = ALIGN(16);
    _stack_top = 0x00030000 - 4;    /* top of DMEM */

    /DISCARD/ : { *(.comment) *(.note.*) *(.eh_frame*) }
}
