// ============================================================================
// clk_rst.v  --  Clock pass-through + reset synchronizer.
//
//   Input:  clk_in (100 MHz from Nexys A7 E3 pin), btn_resetn (CPU_RESETN, active-low)
//   Output: clk_out  = clk_in  (no PLL needed; 100 MHz direct)
//           rst_n_sync = synchronized active-low reset, held low for
//                        RST_HOLD cycles after power-up or button press.
// ============================================================================
`timescale 1ns/1ps

module clk_rst #(
    parameter RST_HOLD = 16
) (
    input  wire clk_in,
    input  wire btn_resetn,
    output wire clk_out,
    output reg  rst_n_sync
);

    assign clk_out = clk_in;

    reg [1:0] sync_ff;
    reg [4:0] cnt;

    always @(posedge clk_in or negedge btn_resetn) begin
        if (!btn_resetn) begin
            sync_ff    <= 2'b00;
            cnt        <= 5'd0;
            rst_n_sync <= 1'b0;
        end else begin
            sync_ff <= {sync_ff[0], 1'b1};
            if (sync_ff[1]) begin
                if (cnt == RST_HOLD-1)
                    rst_n_sync <= 1'b1;
                else
                    cnt <= cnt + 5'd1;
            end
        end
    end

endmodule
