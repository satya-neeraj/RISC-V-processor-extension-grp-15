// tb_div.v  --  Verify div_unit.v with RISC-V semantics.
`timescale 1ns/1ps

module tb_div;
    reg         clk = 0, rst_n = 0, start = 0;
    reg  [31:0] a, b;
    wire [31:0] q, r;
    wire        busy, done;

    div_unit dut(.clk(clk), .rst_n(rst_n), .start(start),
                 .a(a), .b(b), .quotient(q), .remainder(r),
                 .busy(busy), .done(done));

    always #5 clk = ~clk;

    integer fails = 0;
    task runcase(input signed [31:0] ina, input signed [31:0] inb);
        reg signed [31:0] expq, expr;
        begin
            @(posedge clk); a <= ina; b <= inb; start <= 1;
            @(posedge clk); start <= 0;
            wait (done);
            @(posedge clk);
            if (inb == 0) begin expq = 32'hFFFFFFFF; expr = ina; end
            else          begin expq = ina / inb; expr = ina - (expq*inb); end
            if (q !== expq || r !== expr) begin
                $display("FAIL a=%0d b=%0d got q=%0d r=%0d exp q=%0d r=%0d",
                          ina, inb, q, r, expq, expr);
                fails = fails + 1;
            end else begin
                $display("PASS a=%0d b=%0d q=%0d r=%0d", ina, inb, q, r);
            end
        end
    endtask

    initial begin
        #20 rst_n = 1;
        runcase(32'sd7, 32'sd2);
        runcase(-32'sd7, 32'sd2);
        runcase(32'sd7, -32'sd2);
        runcase(-32'sd7, -32'sd2);
        runcase(32'sd0, 32'sd5);
        runcase(32'sd100, 32'sd1);
        runcase(32'sd5, 32'sd0);          // div-by-zero
        runcase(-32'sd5, 32'sd0);         // div-by-zero signed
        if (fails == 0) $display("\nALL DIV TESTS PASSED");
        else            $display("\n%0d DIV TESTS FAILED", fails);
        $finish;
    end
endmodule
