// /* ===========================================================================
//  * main.c  --  NN inference driver for riscv_nn_soc
//  *
//  * On reset, startup.S jumps here.  This function:
//  *   1. Marks NN inference active (starts counting nn_inference_cycles).
//  *   2. Runs the hidden fully-connected + ReLU layer (196 -> 64).
//  *   3. Runs the output fully-connected layer (64 -> 10).
//  *   4. Converts output scores to probabilities via CORDIC arctan scaling.
//  *   5. argmax(probs) -> predicted digit.
//  *   6. Marks NN inactive and prints results + CSR counters over UART.
//  *
//  * All tensors live at fixed addresses in DMEM (see nn_driver.h).
//  * =========================================================================== */
// #include <stdint.h>
// #include "uart_driver.h"
// #include "nn_driver.h"

// #define INPUT_DIM   196
// #define HIDDEN_DIM   64
// #define OUTPUT_DIM   10

// static const int32_t *input  = (const int32_t *)INPUT_ADDR;
// static const int32_t *W1     = (const int32_t *)W1_ADDR;
// static const int32_t *b1     = (const int32_t *)B1_ADDR;
// static int32_t       *H1    = (int32_t *)H1_ADDR;
// static const int32_t *W2     = (const int32_t *)W2_ADDR;
// static const int32_t *b2     = (const int32_t *)B2_ADDR;
// static int32_t       *scores = (int32_t *)SCORES_ADDR;
// static int32_t       *probs  = (int32_t *)PROBS_ADDR;

// static void print_counter(const char *label, uint32_t v) {
//     uart_puts(label);
//     uart_put_udec(v);
//     uart_puts("\r\n");
// }

// int main(void) {
//     /* ---------- Phase 1: start measurement ------------------------------- */
//     nn_mark_active(1);
//     uint32_t t0 = *((volatile uint32_t *)CSR_TOTAL);

//     /* ---------- Phase 2: hidden layer 196 -> 64 with ReLU --------------- */
//     nn_layer_fc_relu(W1, b1, input, H1, INPUT_DIM, HIDDEN_DIM);

//     /* ---------- Phase 3: output layer 64 -> 10 (no activation) --------- */
//     nn_layer_fc(W2, b2, H1, scores, HIDDEN_DIM, OUTPUT_DIM);

//     /* ---------- Phase 4: CORDIC probability scaling -------------------- */
//     nn_probs_from_scores(scores, probs, OUTPUT_DIM);

//     /* ---------- Phase 5: argmax in software ---------------------------- */
//     int predicted = nn_argmax(probs, OUTPUT_DIM);
//     int32_t p     = probs[predicted];

//     /* ---------- Phase 6: stop measurement + print ---------------------- */
//     nn_mark_active(0);

//     uart_puts("\r\n====================================\r\n");
//     uart_puts("PREDICTED DIGIT : ");
//     uart_put_udec((uint32_t)predicted);
//     uart_puts("\r\n");

//     uart_puts("PROBABILITY     : ");
//     uart_put_q16_16(p);
//     uart_puts("\r\n\r\n");

//     /* CSR counters */
//     print_counter("TOTAL CYCLES          : ", *((volatile uint32_t *)CSR_TOTAL));
//     print_counter("MUL CYCLES            : ", *((volatile uint32_t *)CSR_MUL));
//     print_counter("DIV CYCLES            : ", *((volatile uint32_t *)CSR_DIV));
//     print_counter("MAC CYCLES            : ", *((volatile uint32_t *)CSR_MAC));
//     print_counter("CORDIC CYCLES         : ", *((volatile uint32_t *)CSR_CORDIC));
//     print_counter("FRONTEND STALL CYCLES : ", *((volatile uint32_t *)CSR_FE_STALL));
//     print_counter("FULL STALL CYCLES     : ", *((volatile uint32_t *)CSR_FULL_STALL));
//     print_counter("DMA CYCLES            : ", *((volatile uint32_t *)CSR_DMA));
//     print_counter("NN INFERENCE CYCLES   : ", *((volatile uint32_t *)CSR_NN_INFER));

//     /* Accelerator utilization = (MAC + CORDIC + MUL + DIV + DMA) / NN_INFER * 100 */
//     uint32_t total_accel = *((volatile uint32_t *)CSR_MAC) +
//                            *((volatile uint32_t *)CSR_CORDIC) +
//                            *((volatile uint32_t *)CSR_MUL) +
//                            *((volatile uint32_t *)CSR_DIV) +
//                            *((volatile uint32_t *)CSR_DMA);
//     uint32_t nn_cycles = *((volatile uint32_t *)CSR_NN_INFER);
//     uint32_t util_bp = 0;   /* basis points 0..10000 */
//     if (nn_cycles > 0) {
//         /* total_accel * 10000 / nn_cycles -- avoid overflow */
//         util_bp = (uint32_t)((uint64_t)total_accel * 10000ull / nn_cycles);
//     }
//     uart_puts("ACCELERATOR UTILIZATION : ");
//     uart_put_udec(util_bp / 100);
//     uart_putc('.');
//     uint32_t f = util_bp % 100;
//     if (f < 10) uart_putc('0');
//     uart_put_udec(f);
//     uart_puts("%\r\n");
//     uart_puts("====================================\r\n");

//     /* Hang (demo done) */
//     for (;;) { }

//     (void)t0;
//     return 0;
// }

/* ===========================================================================
 * main.c  --  Sequential demo for riscv_nn_soc
 *
 * Layout:
 *   [BANNER]
 *   [MUL    TEST]  - verify custom MUL opcode
 *   [DIV    TEST]  - verify custom DIV opcode
 *   [MAC    TEST]  - verify MAC.CLR + MAC.ACC + MAC.RD  (multi-cycle!)
 *   [CORDIC TEST]  - verify arctan
 *   [NN     TEST]  - full 196->64->10 inference  (the big one)
 *   [DONE]
 *
 * Why sequential?
 *   If the board hangs, you see EXACTLY which block failed by the last
 *   banner printed over UART.  This is far easier to debug on a demo
 *   day than watching a silent PuTTY.
 *
 * Why no "fixed delay" between blocks?
 *   Every custom-opcode instruction STALLS the pipeline until the
 *   accelerator's 'done' flag fires.  The CPU literally cannot move on
 *   until the accelerator is ready.  There's no race -- we don't need
 *   a delay.  If you WANT a visible delay so the LEDs on the Nexys
 *   have time to show each phase, a small busy-wait is added at the
 *   end of each block.
 * =========================================================================== */
#include <stdint.h>
#include "uart_driver.h"
#include "nn_driver.h"

#define INPUT_DIM    196
#define HIDDEN_DIM    64
#define OUTPUT_DIM    10

/* ---- NN tensors (addresses defined in nn_driver.h) ------------------- */
static const int32_t *input  = (const int32_t *)INPUT_ADDR;
static const int32_t *W1     = (const int32_t *)W1_ADDR;
static const int32_t *b1     = (const int32_t *)B1_ADDR;
static int32_t       *H1     = (int32_t *)H1_ADDR;
static const int32_t *W2     = (const int32_t *)W2_ADDR;
static const int32_t *b2     = (const int32_t *)B2_ADDR;
static int32_t       *scores = (int32_t *)SCORES_ADDR;
static int32_t       *probs  = (int32_t *)PROBS_ADDR;

/* ---- Busy-wait (visible LED phase between blocks) --------------------- */
static void busy_delay(uint32_t loops) {
    volatile uint32_t i;
    for (i = 0; i < loops; i++) { /* nothing */ }
}

static void print_header(const char *name) {
    uart_puts("\r\n----- ");
    uart_puts(name);
    uart_puts(" -----\r\n");
}

static void print_kv_hex(const char *k, int32_t v) {
    uart_puts(k);
    uart_put_hex((uint32_t)v);
    uart_puts("\r\n");
}

static void print_kv_dec(const char *k, int32_t v) {
    uart_puts(k);
    uart_put_dec(v);
    uart_puts("\r\n");
}

static void print_kv_q(const char *k, int32_t v) {
    uart_puts(k);
    uart_put_q16_16(v);
    uart_puts("\r\n");
}

/* ==========================================================================
 *                                BLOCKS
 * ========================================================================== */

static void banner(void) {
    uart_puts("\r\n");
    uart_puts("====================================\r\n");
    uart_puts("  riscv_nn_soc  --  Sequential Demo\r\n");
    uart_puts("====================================\r\n");
}

/* ---- [MUL TEST] ------------------------------------------------------- */
static void test_mul(void) {
    print_header("MUL TEST");
    int32_t a = 7, b = 6;
    int32_t r = nn_mul(a, b);
    print_kv_dec("  a      = ", a);
    print_kv_dec("  b      = ", b);
    print_kv_dec("  a * b  = ", r);
    uart_puts((r == 42) ? "  RESULT : PASS\r\n" : "  RESULT : FAIL\r\n");
}

/* ---- [DIV TEST] ------------------------------------------------------- */
static void test_div(void) {
    print_header("DIV TEST");
    int32_t a = 100, b = 7;
    int32_t q = nn_div(a, b);    /* expect 14 */
    int32_t m = nn_rem(a, b);    /* expect 2  */
    print_kv_dec("  a      = ", a);
    print_kv_dec("  b      = ", b);
    print_kv_dec("  a / b  = ", q);
    print_kv_dec("  a % b  = ", m);
    uart_puts((q == 14 && m == 2) ? "  RESULT : PASS\r\n" : "  RESULT : FAIL\r\n");
}

/* ---- [MAC TEST] ------------------------------------------------------- */
/* Q16.16:  1.0=0x00010000  1.5=0x00018000  2.0=0x00020000 */
static void test_mac(void) {
    print_header("MAC TEST (Q16.16)");
    mac_clr();
    mac_acc(0x00010000, 0x00010000);    /* 1.0 * 1.0 = 1.0 */
    mac_acc(0x00018000, 0x00020000);    /* 1.5 * 2.0 = 3.0 */
    int32_t acc = mac_rd();             /* expect 4.0 = 0x00040000 */
    print_kv_hex("  acc(hex) = ", acc);
    print_kv_q  ("  acc(dec) = ", acc);
    uart_puts((acc == 0x00040000) ? "  RESULT : PASS\r\n" : "  RESULT : FAIL\r\n");
}

/* ---- [CORDIC TEST] ---------------------------------------------------- */
/* atan(1.0) = pi/4 = 0.7854  ~= 0x0000C911 in Q16.16 */
static void test_cordic(void) {
    print_header("CORDIC TEST (Q16.16)");
    int32_t x = 0x00010000;                      /* 1.0 */
    int32_t y = cordic_atan(x);                  /* expect ~0xC911 */
    print_kv_hex("  atan(1.0) hex = ", y);
    print_kv_q  ("  atan(1.0) dec = ", y);
    /* acceptable range: 0.78 .. 0.79 in Q16.16 = 0xC7AE..0xCA3D */
    int32_t lo = 0x0000C700, hi = 0x0000CB00;
    uart_puts((y > lo && y < hi) ? "  RESULT : PASS\r\n" : "  RESULT : FAIL\r\n");
}

/* ---- [NN TEST] -------------------------------------------------------- */
static void test_nn(void) {
    print_header("NN TEST  (196 -> 64 -> 10)");
    uart_puts("  Starting inference...\r\n");
    nn_mark_active(1);

    nn_layer_fc_relu(W1, b1, input, H1, INPUT_DIM, HIDDEN_DIM);
    uart_puts("  Hidden layer  : DONE\r\n");

    nn_layer_fc(W2, b2, H1, scores, HIDDEN_DIM, OUTPUT_DIM);
    uart_puts("  Output layer  : DONE\r\n");

    nn_probs_from_scores(scores, probs, OUTPUT_DIM);
    uart_puts("  Probability   : DONE\r\n");

    int     pred = nn_argmax(probs, OUTPUT_DIM);
    int32_t p    = probs[pred];
    nn_mark_active(0);

    uart_puts("\r\n");
    print_kv_dec("  PREDICTED DIGIT : ", pred);
    print_kv_q  ("  PROBABILITY     : ", p);

    /* Cycle counters */
    uint32_t cnn  = *((volatile uint32_t *)CSR_NN_INFER);
    uint32_t cmac = *((volatile uint32_t *)CSR_MAC);
    uint32_t ccor = *((volatile uint32_t *)CSR_CORDIC);
    print_kv_dec("  NN    CYCLES    : ", (int32_t)cnn);
    print_kv_dec("  MAC   CYCLES    : ", (int32_t)cmac);
    print_kv_dec("  CORDIC CYCLES   : ", (int32_t)ccor);
}

/* ==========================================================================
 *                                  MAIN
 * ========================================================================== */
int main(void) {
    banner();

    test_mul();     busy_delay(200000);
    // test_div();     busy_delay(200000);
    // test_mac();     busy_delay(200000);
    // test_cordic();  busy_delay(200000);
    // test_nn();

    uart_puts("\r\n====================================\r\n");
    uart_puts("              DEMO DONE\r\n");
    uart_puts("====================================\r\n");

    for (;;) { }
    return 0;
}