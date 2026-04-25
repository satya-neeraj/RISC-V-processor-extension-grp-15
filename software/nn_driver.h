/* ===========================================================================
 * nn_driver.h  --  Wrappers for custom-opcode accelerators
 *
 * Custom opcode encoding (see rtl/opcode.vh):
 *   MUL  : opcode=0x0B funct3=0b000 funct7=0
 *   DIV  : opcode=0x0B funct3=0b001 funct7=0
 *   REM  : opcode=0x0B funct3=0b010 funct7=0
 *   MAC_CLR : opcode=0x2B funct3=0b000
 *   MAC_ACC : opcode=0x2B funct3=0b001
 *   MAC_RD  : opcode=0x2B funct3=0b010
 *   ASIN    : opcode=0x5B funct3=0b000
 *   ACOS    : opcode=0x5B funct3=0b001
 *   ATAN    : opcode=0x5B funct3=0b010
 *   DMA_SRC : opcode=0x7B funct3=0b000
 *   DMA_DST : opcode=0x7B funct3=0b001
 *   DMA_LEN : opcode=0x7B funct3=0b010
 *   DMA_GO  : opcode=0x7B funct3=0b011
 *
 * Since riscv32-unknown-elf-gcc does not know these opcodes, we emit the
 * raw 32-bit R-type words via .word.  rs1/rs2/rd are encoded at fixed register
 * positions: here we pin them to a0/a1/a0 (x10/x11/x10) and use inline asm
 * to move values in/out of those registers around each custom instruction.
 * =========================================================================== */
#ifndef NN_DRIVER_H
#define NN_DRIVER_H

#include <stdint.h>

/* ---- Memory map -------------------------------------------------------- */
#define DMEM_BASE        0x00010000u
#define INPUT_ADDR       (DMEM_BASE + 0x00000)   /* 196 words */
#define W1_ADDR          (DMEM_BASE + 0x01000)   /* 12544 words */
#define B1_ADDR          (DMEM_BASE + 0x0E000)   /* 64 words */
#define H1_ADDR          (DMEM_BASE + 0x0E100)   /* 64 words */
#define W2_ADDR          (DMEM_BASE + 0x0E200)   /* 640 words */
#define B2_ADDR          (DMEM_BASE + 0x0EC00)   /* 10 words */
#define SCORES_ADDR      (DMEM_BASE + 0x0EC40)   /* 10 words */
#define PROBS_ADDR       (DMEM_BASE + 0x0EC80)   /* 10 words */

#define CSR_TOTAL        0x10001000
#define CSR_MUL          0x10001004
#define CSR_DIV          0x10001008
#define CSR_MAC          0x1000100C
#define CSR_CORDIC       0x10001010
#define CSR_FE_STALL     0x10001014
#define CSR_FULL_STALL   0x10001018
#define CSR_DMA          0x1000101C
#define CSR_NN_INFER     0x10001020
#define CSR_NN_ACTIVE    0x10001024  /* write-only: set/clear NN active flag */

/* ---- Custom-opcode wrappers (each forces rs1=a0, rs2=a1, rd=a0) ------- */
int32_t nn_mul(int32_t a, int32_t b);
int32_t nn_div(int32_t a, int32_t b);
int32_t nn_rem(int32_t a, int32_t b);

void    mac_clr(void);
void    mac_acc(int32_t a_q16_16, int32_t b_q16_16);
int32_t mac_rd(void);

int32_t cordic_asin(int32_t x_q16_16);
int32_t cordic_acos(int32_t x_q16_16);
int32_t cordic_atan(int32_t x_q16_16);

void    dma_set_src(uint32_t src);
void    dma_set_dst(uint32_t dst);
void    dma_set_len(uint32_t len_words);
void    dma_go(void);

/* ---- NN layer ops (high-level) ---------------------------------------- */
void nn_mark_active(int active);
void nn_layer_fc_relu(const int32_t *W, const int32_t *b,
                      const int32_t *x, int32_t *y,
                      int in_dim, int out_dim);
void nn_layer_fc(const int32_t *W, const int32_t *b,
                 const int32_t *x, int32_t *y,
                 int in_dim, int out_dim);
int  nn_argmax(const int32_t *v, int n);
void nn_probs_from_scores(const int32_t *scores, int32_t *probs, int n);

#endif
