// tb_cordic.v  --  Exercise CORDIC asin/acos/atan with Q16.16 inputs.
`timescale 1ns/1ps

module tb_cordic;
    reg         clk = 0, rst_n = 0, start = 0;
    reg  [1:0]  mode;
    reg  [31:0] x_in;
    wire [31:0] result;
    wire        busy, done;

    cordic_unit dut(.clk(clk), .rst_n(rst_n),
                    .start(start), .mode(mode), .x_in(x_in),
                    .result(result),
                    .busy(busy), .done(done));

    always #5 clk = ~clk;

    task runcase(input [1:0] m, input [31:0] x, input [31:0] label);
        begin
            @(posedge clk); mode <= m; x_in <= x; start <= 1;
            @(posedge clk); start <= 0;
            wait (done);
            @(posedge clk);
            $display("mode=%0d x=0x%08X  result=0x%08X  ~%f",
                     m, x, result,
                     $itor($signed(result)) / 65536.0);
        end
    endtask

    initial begin
        #20 rst_n = 1;
        runcase(2'b10, 32'h0000_8000, 0);  // atan(0.5)  ~ 0.4636
        runcase(2'b10, 32'h0001_0000, 0);  // atan(1.0)  ~ 0.7854
        runcase(2'b10, 32'hFFFF_8000, 0);  // atan(-0.5) ~ -0.4636
        runcase(2'b00, 32'h0000_8000, 0);  // asin(0.5)  ~ 0.5236
        runcase(2'b01, 32'h0000_8000, 0);  // acos(0.5)  ~ 1.0472
        runcase(2'b10, 32'h0000_0000, 0);  // atan(0)    = 0
        $finish;
    end
endmodule
