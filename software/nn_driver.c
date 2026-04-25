/* ===========================================================================
 * nn_driver.c  --  Custom-opcode wrappers and NN layer routines.
 *
 * ---------------------------------------------------------------------------
 * WHY THIS FILE USES LITERAL .word ENCODINGS (and not '%c' inline asm)
 * ---------------------------------------------------------------------------
 * Modern RISC-V GCC toolchains (xPack riscv-none-elf-gcc, GCC 13.x, etc.)
 * do not accept the '.word %c0' trick for emitting a runtime-computed
 * instruction word, because the assembler needs the 32-bit constant at
 * assembly time -- not a C expression.  Since every custom-opcode instruction
 * in this NN SoC uses *fixed* register fields (rd = rs1 = a0, rs2 = a1,
 * funct7 = 0), each instruction is itself a fixed 32-bit constant.  We just
 * emit that constant with '.word 0xXXXXXXXX' -- portable across every
 * RISC-V toolchain, no GCC extensions.
 *
 * R-type layout: [funct7=0][rs2=11][rs1=10][funct3][rd=10][opcode]
 *
 *   MUL     0x0B f3=000 -> 0x00B5050B
 *   DIV     0x0B f3=001 -> 0x00B5150B
 *   REM     0x0B f3=010 -> 0x00B5250B
 *   MAC_CLR 0x2B f3=000 -> 0x00B5052B
 *   MAC_ACC 0x2B f3=001 -> 0x00B5152B
 *   MAC_RD  0x2B f3=010 -> 0x00B5252B
 *   ASIN    0x5B f3=000 -> 0x00B5055B
 *   ACOS    0x5B f3=001 -> 0x00B5155B
 *   ATAN    0x5B f3=010 -> 0x00B5255B
 *   DMA_SRC 0x7B f3=000 -> 0x00B5057B
 *   DMA_DST 0x7B f3=001 -> 0x00B5157B
 *   DMA_LEN 0x7B f3=010 -> 0x00B5257B
 *   DMA_GO  0x7B f3=011 -> 0x00B5357B
 *
 * Register pinning uses the GCC '__asm__("a0")' / '__asm__("a1")' register
 * variable syntax to force operands into x10/x11 before the custom instr
 * executes.  This is supported by GCC 4.x through 14.x without change.
 * ===========================================================================
 */
#include "nn_driver.h"

/* ---- MMIO helpers ------------------------------------------------------- */
static inline uint32_t mmio_rd(uint32_t addr) {
    return *((volatile uint32_t *)addr);
}
static inline void mmio_wr(uint32_t addr, uint32_t val) {
    *((volatile uint32_t *)addr) = val;
}

/* ===========================================================================
 * MUL / DIV / REM   (custom opcode 0x0B)
 * rd=a0, rs1=a0, rs2=a1
 * =========================================================================== */
int32_t nn_mul(int32_t a, int32_t b) {
    register int32_t _a __asm__("a0") = a;
    register int32_t _b __asm__("a1") = b;
    __asm__ volatile (".word 0x00B5050B"
                      : "+r"(_a)
                      : "r"(_b));
    return _a;
}

int32_t nn_div(int32_t a, int32_t b) {
    register int32_t _a __asm__("a0") = a;
    register int32_t _b __asm__("a1") = b;
    __asm__ volatile (".word 0x00B5150B"
                      : "+r"(_a)
                      : "r"(_b));
    return _a;
}

int32_t nn_rem(int32_t a, int32_t b) {
    register int32_t _a __asm__("a0") = a;
    register int32_t _b __asm__("a1") = b;
    __asm__ volatile (".word 0x00B5250B"
                      : "+r"(_a)
                      : "r"(_b));
    return _a;
}

/* ===========================================================================
 * MAC accelerator   (custom opcode 0x2B)
 * =========================================================================== */
void mac_clr(void) {
    __asm__ volatile (".word 0x00B5052B" ::: "memory");
}

void mac_acc(int32_t a, int32_t b) {
    register int32_t _a __asm__("a0") = a;
    register int32_t _b __asm__("a1") = b;
    __asm__ volatile (".word 0x00B5152B"
                      :
                      : "r"(_a), "r"(_b)
                      : "memory");
}

int32_t mac_rd(void) {
    register int32_t _a __asm__("a0");
    __asm__ volatile (".word 0x00B5252B"
                      : "=r"(_a));
    return _a;
}

/* ===========================================================================
 * CORDIC   (custom opcode 0x5B)   rd = fn(rs1)
 * =========================================================================== */
int32_t cordic_asin(int32_t x) {
    register int32_t _a __asm__("a0") = x;
    __asm__ volatile (".word 0x00B5055B"
                      : "+r"(_a));
    return _a;
}

int32_t cordic_acos(int32_t x) {
    register int32_t _a __asm__("a0") = x;
    __asm__ volatile (".word 0x00B5155B"
                      : "+r"(_a));
    return _a;
}

int32_t cordic_atan(int32_t x) {
    register int32_t _a __asm__("a0") = x;
    __asm__ volatile (".word 0x00B5255B"
                      : "+r"(_a));
    return _a;
}

/* ===========================================================================
 * DMA   (custom opcode 0x7B)
 * =========================================================================== */
void dma_set_src(uint32_t src) {
    register int32_t _a __asm__("a0") = (int32_t)src;
    __asm__ volatile (".word 0x00B5057B"
                      :
                      : "r"(_a)
                      : "memory");
}

void dma_set_dst(uint32_t dst) {
    register int32_t _a __asm__("a0") = (int32_t)dst;
    __asm__ volatile (".word 0x00B5157B"
                      :
                      : "r"(_a)
                      : "memory");
}

void dma_set_len(uint32_t len) {
    register int32_t _a __asm__("a0") = (int32_t)len;
    __asm__ volatile (".word 0x00B5257B"
                      :
                      : "r"(_a)
                      : "memory");
}

void dma_go(void) {
    __asm__ volatile (".word 0x00B5357B" ::: "memory");
}

/* ===========================================================================
 * NN-inference support
 * =========================================================================== */
void nn_mark_active(int active) {
    mmio_wr(CSR_NN_ACTIVE, active ? 1u : 0u);
}

static inline int32_t q_relu(int32_t x) { return (x > 0) ? x : 0; }

/* Fully-connected layer using the MAC accelerator; output index j:
 *   y[j] = relu( sum_i W[j*in_dim + i] * x[i]  +  b[j] )
 */
void nn_layer_fc_relu(const int32_t *W, const int32_t *b,
                      const int32_t *x, int32_t *y,
                      int in_dim, int out_dim) {
    for (int j = 0; j < out_dim; j++) {
        mac_clr();
        const int32_t *wrow = W + j * in_dim;
        for (int i = 0; i < in_dim; i++) {
            mac_acc(wrow[i], x[i]);
        }
        int32_t s = mac_rd();
        s += b[j];
        y[j] = q_relu(s);
    }
}

/* Same without ReLU (used for the output layer before probability scaling). */
void nn_layer_fc(const int32_t *W, const int32_t *b,
                 const int32_t *x, int32_t *y,
                 int in_dim, int out_dim) {
    for (int j = 0; j < out_dim; j++) {
        mac_clr();
        const int32_t *wrow = W + j * in_dim;
        for (int i = 0; i < in_dim; i++) {
            mac_acc(wrow[i], x[i]);
        }
        int32_t s = mac_rd();
        s += b[j];
        y[j] = s;
    }
}

int nn_argmax(const int32_t *v, int n) {
    int idx = 0;
    int32_t best = v[0];
    for (int i = 1; i < n; i++) {
        if (v[i] > best) { best = v[i]; idx = i; }
    }
    return idx;
}

/* Probability scaling using CORDIC arctan.
 *   p_i = (atan(s_i) * (1 / (pi/2)) + 1) / 2   -- maps to [0, 1]
 *   renormalize so they sum to 1.
 *   All math in Q16.16 signed.
 */
void nn_probs_from_scores(const int32_t *scores, int32_t *probs, int n) {
    int32_t acc = 0;

    /* Step 1: per-score (atan(s)/pi_2 + 1)/2 */
    for (int i = 0; i < n; i++) {
        int32_t a = cordic_atan(scores[i]);     /* Q16.16 */
        /* 1/(pi/2) ~= 0.6366 ~= 41721 in Q16.16 */
        mac_clr();
        mac_acc(a, 41721);
        int32_t r = mac_rd();                   /* Q16.16 */
        r = (r + 0x10000) >> 1;                 /* (r+1)/2 */
        probs[i] = r;
        acc += r;
    }

    /* Step 2: normalize:  p_i /= acc  */
    if (acc > 0) {
        int32_t inv = nn_div((int32_t)(1 << 16), acc);   /* Q0.16 */
        for (int i = 0; i < n; i++) {
            mac_clr();
            mac_acc(probs[i], inv);
            probs[i] = mac_rd();
        }
    }
}
