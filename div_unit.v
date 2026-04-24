// ============================================================================
// div_unit.v  --  Signed 32/32 divider, restoring algorithm, 32 cycles
//
// Produces quotient and remainder.  The caller (ex_stage) selects which one
// to write back for DIV vs REM.
//
// Handshake:  start pulse -> busy=1 for 32 clocks -> done pulses 1 cycle.
// Divide-by-zero: quotient = 32'hFFFFFFFF, remainder = dividend (RISC-V conv.)
// ============================================================================
`timescale 1ns/1ps

module div_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] a,         // dividend
    input  wire [31:0] b,         // divisor
    output reg  [31:0] quotient,
    output reg  [31:0] remainder,
    output reg         busy,
    output reg         done
);

    reg         [31:0] abs_a, abs_b;
    reg                sign_q, sign_r;
    reg  signed [32:0] R;        // remainder register (one extra bit for sub)
    reg         [31:0] Q;
    reg         [31:0] D;        // |b|
    reg         [5:0]  iter;     // 0..32
    reg                div_by_zero;

    wire signed [32:0] R_shift = {R[31:0], Q[31]};     // << 1 bring in next bit
    wire signed [32:0] R_try   = R_shift - {1'b0, D};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            abs_a <= 0; abs_b <= 0;
            sign_q <= 0; sign_r <= 0;
            R <= 0; Q <= 0; D <= 0;
            iter <= 0;
            busy <= 0; done <= 0;
            quotient <= 0; remainder <= 0;
            div_by_zero <= 0;
        end else begin
            done <= 1'b0;
            if (!busy && start) begin
                abs_a       <= a[31] ? (~a + 1) : a;
                abs_b       <= b[31] ? (~b + 1) : b;
                sign_q      <= a[31] ^ b[31];
                sign_r      <= a[31];
                R           <= 33'sd0;
                Q           <= a[31] ? (~a + 1) : a;   // we shift Q left each iter
                D           <= b[31] ? (~b + 1) : b;
                iter        <= 6'd0;
                busy        <= 1'b1;
                div_by_zero <= (b == 32'b0);
            end else if (busy) begin
                if (div_by_zero) begin
                    // RISC-V: quotient = -1, remainder = dividend
                    quotient  <= 32'hFFFF_FFFF;
                    remainder <= sign_r ? (~abs_a + 1) : abs_a;
                    busy      <= 1'b0;
                    done      <= 1'b1;
                end else begin
                    if (R_try >= 0) begin
                        R <= R_try;
                        Q <= {Q[30:0], 1'b1};
                    end else begin
                        R <= R_shift;
                        Q <= {Q[30:0], 1'b0};
                    end
                    iter <= iter + 6'd1;
                    if (iter == 6'd31) begin
                        // finalize on this cycle
                        quotient  <= sign_q ? (~({Q[30:0], (R_try >= 0) ? 1'b1 : 1'b0}) + 1)
                                            :        {Q[30:0], (R_try >= 0) ? 1'b1 : 1'b0};
                        remainder <= sign_r ? (~((R_try >= 0) ? R_try[31:0] : R_shift[31:0]) + 1)
                                            :        ((R_try >= 0) ? R_try[31:0] : R_shift[31:0]);
                        busy <= 1'b0;
                        done <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
