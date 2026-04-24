// ============================================================================
// clk_rst.v  --  Clock pass-through + reset synchronizer.
//
//   Input:  clk_in (100 MHz from Nexys A7 E3 pin), btn_resetn (CPU_RESETN, active-low)
//   Output: clk_out  = clk_in  (no PLL needed; 100 MHz direct)
//           rst_n_sync = synchronized active-low reset, held low for
//                        RST_HOLD cycles after power-up or button press.
// ============================================================================
// clk_rst.v  -- 100 MHz in, 50 MHz out, with synchronous reset release

`timescale 1ns/1ps
module clk_rst #(parameter RST_HOLD = 16) (
    input  wire clk_in,          // 100 MHz from E3 pin
    input  wire btn_resetn,
    output wire clk_out,         // 50 MHz to rest of design
    output reg  rst_n_sync
);
    wire clk_fb, clk50_unbuf, mmcm_locked;

    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.0),    // 10 ns = 100 MHz in
        .CLKFBOUT_MULT_F(10.0),  // VCO = 1000 MHz
        .CLKOUT0_DIVIDE_F(20.0), // 1000/20 = 50 MHz out
        .DIVCLK_DIVIDE(1)
    ) u_mmcm (
        .CLKIN1(clk_in), .CLKFBIN(clk_fb), .RST(1'b0),
        .CLKOUT0(clk50_unbuf), .CLKFBOUT(clk_fb),
        .LOCKED(mmcm_locked),
        .PWRDWN(1'b0)
    );

    BUFG u_bufg (.I(clk50_unbuf), .O(clk_out));

    reg [1:0] sync_ff;
    reg [4:0] cnt;
    always @(posedge clk_out or negedge btn_resetn) begin
        if (!btn_resetn) begin
            sync_ff <= 2'b00; cnt <= 0; rst_n_sync <= 1'b0;
        end else if (!mmcm_locked) begin
            sync_ff <= 2'b00; cnt <= 0; rst_n_sync <= 1'b0;
        end else begin
            sync_ff <= {sync_ff[0], 1'b1};
            if (sync_ff[1]) begin
                if (cnt == RST_HOLD-1) rst_n_sync <= 1'b1;
                else                   cnt <= cnt + 1;
            end
        end
    end
endmodule