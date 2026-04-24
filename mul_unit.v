// ============================================================================
// mul_unit.v  --  Radix-4 Booth signed 32x32 multiplier, 16 cycles
//
// Handshake:  start pulse -> busy=1 for 16 clocks -> done pulses 1 cycle
//             result valid when done==1.
// ============================================================================
`timescale 1ns/1ps

module mul_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] a,        // multiplicand
    input  wire [31:0] b,        // multiplier
    output reg  [31:0] result,
    output reg         busy,
    output reg         done
);

    reg  signed [32:0] A;
    reg         [31:0] Q;
    reg                Qm1;
    reg         [31:0] M;
    reg         [4:0]  iter;

    wire signed [32:0] M_ext  = {M[31], M};
    wire signed [32:0] two_M  = M_ext <<< 1;
    wire signed [32:0] neg_M  = -M_ext;
    wire signed [32:0] neg_2M = -two_M;

    wire [2:0] booth = {Q[1:0], Qm1};

    reg signed [32:0] A_add;
    always @(*) begin
        case (booth)
            3'b001, 3'b010: A_add = A + M_ext;
            3'b011        : A_add = A + two_M;
            3'b100        : A_add = A + neg_2M;
            3'b101, 3'b110: A_add = A + neg_M;
            default       : A_add = A;
        endcase
    end

    wire signed [65:0] cat_pre  = {A_add, Q, Qm1};
    wire signed [65:0] cat_post = cat_pre >>> 2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A      <= 33'sd0;
            Q      <= 32'b0;
            Qm1    <= 1'b0;
            M      <= 32'b0;
            iter   <= 5'd0;
            busy   <= 1'b0;
            done   <= 1'b0;
            result <= 32'b0;
        end else begin
            done <= 1'b0;
            if (!busy && start) begin
                A    <= 33'sd0;
                Q    <= b;
                Qm1  <= 1'b0;
                M    <= a;
                iter <= 5'd0;
                busy <= 1'b1;
            end else if (busy) begin
                {A, Q, Qm1} <= cat_post;
                iter        <= iter + 5'd1;
                if (iter == 5'd15) begin
                    result <= cat_post[32:1];
                    busy   <= 1'b0;
                    done   <= 1'b1;
                end
            end
        end
    end

endmodule
