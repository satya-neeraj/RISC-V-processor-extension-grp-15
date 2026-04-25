// tb_uart.v  --  Check uart_tx.v emits start + 8 data LSB-first + stop
//               at the correct period (here reduced for sim).
`timescale 1ns/1ps

module tb_uart;
    reg clk = 0, rst_n = 0, wr = 0;
    reg  [7:0] data = 0;
    wire       busy, tx;

    always #5 clk = ~clk;

    // For simulation speed, use CLKS_PER_BIT=4 (not 868).
    uart_tx #(.CLKS_PER_BIT(4)) dut(
        .clk(clk), .rst_n(rst_n), .wr(wr), .data(data),
        .busy(busy), .tx(tx)
    );

    initial begin
        $display("%0t tx idle", $time);
        #30 rst_n = 1;
        #10 data = 8'h55; wr = 1;
        #10 wr = 0;
        #800;
        $display("%0t done (tx should be back to 1)", $time);
        $finish;
    end

    initial begin
        $monitor("%0t tx=%b busy=%b", $time, tx, busy);
    end
endmodule
