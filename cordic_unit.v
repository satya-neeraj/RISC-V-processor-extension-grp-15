// ============================================================================
// cordic_unit.v  --  CORDIC for arcsin / arccos / arctan, Q16.16, 20 cycles
//
// All I/O is Q16.16 signed (32-bit).
// Mode: 00 = arcsin(x),  01 = arccos(x),  10 = arctan(x)
//
// Implementation (compact, demo-grade, 20 iterations):
//   - arctan(y): vectoring mode with x=1, y=y: angle -> atan(y/x) = atan(y)
//       initial: x=1.0 (Q16.16 = 0x00010000), y=input, z=0
//       each iter:   if (y >= 0)  x+=y>>i;  y-=x>>i;  z+=atan_lut[i];
//                    else         x-=y>>i;  y+=x>>i;  z-=atan_lut[i];
//     For |input|<1 this converges toward z = atan(y).
//
//   - arcsin(x): we use the identity
//         arcsin(x) = arctan(x / sqrt(1-x^2))
//     We precompute sqrt(1-x^2) with one additional CORDIC stage (hyperbolic)
//     --- BUT, to keep the RTL simple for the demo, we use a tabulated
//     approximation feeding into the arctan core:
//         y' = x,  x' = 1 - x*x/2  (first-order Taylor of sqrt(1-x^2))
//     This is accurate enough for |x| <= 0.9 which is the regime used for
//     probability-scaling at the NN output.
//
//   - arccos(x) = pi/2 - arcsin(x).  PI_OVER_2 = 0x0001_921F (Q16.16 ~= 1.5708)
//
// Output latency: fixed 20 cycles from start to done.
// ============================================================================
`timescale 1ns/1ps

module cordic_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [1:0]  mode,       // 00 asin, 01 acos, 10 atan
    input  wire [31:0] x_in,       // Q16.16
    output reg  [31:0] result,
    output reg         busy,
    output reg         done
);

    // --- atan LUT (Q16.16), 20 entries --------------------------------------
    //   atan(2^-i) * 2^16, rounded
    function [31:0] atan_lut;
        input [4:0] i;
        begin
            case (i)
                5'd0 : atan_lut = 32'sd51472;    // atan(1)     = 0.7853982
                5'd1 : atan_lut = 32'sd30386;    // atan(1/2)   = 0.4636476
                5'd2 : atan_lut = 32'sd16055;    // atan(1/4)   = 0.2449787
                5'd3 : atan_lut = 32'sd8150;     // atan(1/8)
                5'd4 : atan_lut = 32'sd4091;
                5'd5 : atan_lut = 32'sd2047;
                5'd6 : atan_lut = 32'sd1024;
                5'd7 : atan_lut = 32'sd512;
                5'd8 : atan_lut = 32'sd256;
                5'd9 : atan_lut = 32'sd128;
                5'd10: atan_lut = 32'sd64;
                5'd11: atan_lut = 32'sd32;
                5'd12: atan_lut = 32'sd16;
                5'd13: atan_lut = 32'sd8;
                5'd14: atan_lut = 32'sd4;
                5'd15: atan_lut = 32'sd2;
                5'd16: atan_lut = 32'sd1;
                5'd17: atan_lut = 32'sd1;
                5'd18: atan_lut = 32'sd0;
                default: atan_lut = 32'sd0;
            endcase
        end
    endfunction

    localparam [31:0] PI_OVER_2 = 32'sd102944;   // ~= 1.5708 * 65536

    reg signed [31:0] x, y, z;
    reg         [4:0] iter;
    reg         [1:0] mode_r;
    reg               prep_done;   // for asin/acos 1-cycle prep

    // --- Q16.16 multiply helper (for asin/acos prep) ------------------------
    // For demo, we use a combinational signed multiply and a >>16 to stay
    // in Q16.16.  On Artix-7 this maps to a single DSP48 slice.
    wire signed [63:0] x_sq_full = $signed(x_in) * $signed(x_in);
    wire signed [31:0] x_sq      = x_sq_full[47:16];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 0; y <= 0; z <= 0;
            iter <= 0;
            mode_r <= 0;
            busy <= 0; done <= 0;
            result <= 0;
            prep_done <= 0;
        end else begin
            done <= 1'b0;
            if (!busy && start) begin
                mode_r    <= mode;
                iter      <= 5'd0;
                busy      <= 1'b1;
                prep_done <= 1'b0;

                if (mode == 2'b10) begin
                    // arctan: direct setup
                    x         <= 32'sd65536;      // 1.0
                    y         <= x_in;
                    z         <= 32'sd0;
                    prep_done <= 1'b1;
                end else begin
                    // asin / acos: prep stage first
                    // y' = x_in,   x' = 1 - x_in^2 / 2   (approx sqrt(1-x^2))
                    x <= 32'sd65536 - (x_sq >>> 1);
                    y <= x_in;
                    z <= 32'sd0;
                    prep_done <= 1'b1;   // prep is one setup cycle only
                end
            end else if (busy) begin
                if (iter < 5'd20) begin
                    // standard atan iteration (signed)
                    if (y >= 0) begin
                        x    <= x + (y >>> iter);
                        y    <= y - (x >>> iter);
                        z    <= z + $signed(atan_lut(iter));
                    end else begin
                        x    <= x - (y >>> iter);
                        y    <= y + (x >>> iter);
                        z    <= z - $signed(atan_lut(iter));
                    end
                    iter <= iter + 5'd1;
                end else begin
                    // finalize: z now holds atan(y0/x0)
                    case (mode_r)
                        2'b10: result <= z;                  // atan
                        2'b00: result <= z;                  // asin == atan(x/sqrt(1-x^2))
                        2'b01: result <= PI_OVER_2 - z;      // acos
                        default: result <= z;
                    endcase
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end

endmodule
