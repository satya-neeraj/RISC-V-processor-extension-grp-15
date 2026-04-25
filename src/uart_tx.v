//// ============================================================================
//// uart_tx.v  --  8N1 UART transmitter at 115200 baud from a 100 MHz clock.
////   CLKS_PER_BIT = 100_000_000 / 115_200 = 868 (rounded).
////
//// Interface:
////   wr pulse + data[7:0]  -> serializes start, 8 data bits, stop.
////   busy high from wr acceptance until stop bit complete.
//// ============================================================================
//`timescale 1ns/1ps

//module uart_tx #(
//    parameter CLKS_PER_BIT = 434
//) (
//    input  wire        clk,
//    input  wire        rst_n,
//    input  wire        wr,
//    input  wire [7:0]  data,
//    output reg         busy,
//    output reg         tx         // UART line (idle high)
//);

//    localparam S_IDLE  = 2'd0,
//               S_START = 2'd1,
//               S_DATA  = 2'd2,
//               S_STOP  = 2'd3;

//    reg [1:0]  st;
//    reg [15:0] cnt;     // bit-timer
//    reg [2:0]  bit_idx;
//    reg [7:0]  shreg;

//    always @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            st <= S_IDLE;
//            cnt <= 0; bit_idx <= 0;
//            shreg <= 0;
//            busy <= 0; tx <= 1'b1;
//        end else begin
//            case (st)
//                S_IDLE: begin
//                    tx <= 1'b1;
//                    busy <= 1'b0;
//                    if (wr) begin
//                        shreg   <= data;
//                        busy    <= 1'b1;
//                        st      <= S_START;
//                        cnt     <= 0;
//                        bit_idx <= 0;
//                    end
//                end
//                S_START: begin
//                    tx <= 1'b0;     // start bit
//                    if (cnt == CLKS_PER_BIT-1) begin
//                        cnt <= 0;
//                        st  <= S_DATA;
//                    end else cnt <= cnt + 1;
//                end
//                S_DATA: begin
//                    tx <= shreg[bit_idx];
//                    if (cnt == CLKS_PER_BIT-1) begin
//                        cnt <= 0;
//                        if (bit_idx == 3'd7) begin
//                            st <= S_STOP;
//                        end else begin
//                            bit_idx <= bit_idx + 1;
//                        end
//                    end else cnt <= cnt + 1;
//                end
//                S_STOP: begin
//                    tx <= 1'b1;     // stop bit
//                    if (cnt == CLKS_PER_BIT-1) begin
//                        cnt  <= 0;
//                        busy <= 1'b0;
//                        st   <= S_IDLE;
//                    end else cnt <= cnt + 1;
//                end
//            endcase
//        end
//    end

//endmodule

// ============================================================================
// uart_tx.v  --  8N1 UART transmitter
//
// IMPORTANT: CLKS_PER_BIT must be computed from the CLOCK ACTUALLY DRIVING
// THIS MODULE, which is the *output* of the MMCM in clk_rst.v.
//
// In this project:
//   MMCM CLKIN1 = 100 MHz (E3 pin)
//   MMCM VCO    = 100 * 10 / 1 = 1000 MHz
//   MMCM CLKOUT0 = 1000 / 20 = 50 MHz   <-- this drives 'clk' everywhere
//
// For 115200 baud at 50 MHz:
//   CLKS_PER_BIT = 50_000_000 / 115_200 = 434 (rounded)
//
// If the MMCM is changed to a different divider, recompute CLKS_PER_BIT
// and update BOTH the default parameter value here AND the override in
// soc_top.v's uart_tx instantiation.
// ============================================================================
`timescale 1ns/1ps

module uart_tx #(
    parameter CLKS_PER_BIT = 434    // 50 MHz / 115200 baud
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        wr,
    input  wire [7:0]  data,
    output reg         busy,
    output reg         tx         // UART line (idle high)
);

    localparam S_IDLE  = 2'd0,
               S_START = 2'd1,
               S_DATA  = 2'd2,
               S_STOP  = 2'd3;

    reg [1:0]  st;
    reg [15:0] cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            cnt <= 0; bit_idx <= 0;
            shreg <= 0;
            busy <= 0; tx <= 1'b1;
        end else begin
            case (st)
                S_IDLE: begin
                    tx <= 1'b1;
                    busy <= 1'b0;
                    if (wr) begin
                        shreg   <= data;
                        busy    <= 1'b1;
                        st      <= S_START;
                        cnt     <= 0;
                        bit_idx <= 0;
                    end
                end
                S_START: begin
                    tx <= 1'b0;
                    if (cnt == CLKS_PER_BIT-1) begin
                        cnt <= 0;
                        st  <= S_DATA;
                    end else cnt <= cnt + 1;
                end
                S_DATA: begin
                    tx <= shreg[bit_idx];          // LSB-first (8N1 standard)
                    if (cnt == CLKS_PER_BIT-1) begin
                        cnt <= 0;
                        if (bit_idx == 3'd7) begin
                            st <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else cnt <= cnt + 1;
                end
                S_STOP: begin
                    tx <= 1'b1;
                    if (cnt == CLKS_PER_BIT-1) begin
                        cnt  <= 0;
                        busy <= 1'b0;
                        st   <= S_IDLE;
                    end else cnt <= cnt + 1;
                end
            endcase
        end
    end

endmodule
