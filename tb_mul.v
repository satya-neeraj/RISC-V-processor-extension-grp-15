`timescale 1ns/1ps

module tb_mul;

reg clk;
reg rst;
reg start;
reg [31:0] a, b;

wire [31:0] result;
wire busy, done;

// DUT
mul_unit uut (
    .clk(clk),
    .rst_n(~rst),
    .start(start),
    .a(a),
    .b(b),
    .result(result),
    .busy(busy),
    .done(done)
);

// clock
always #5 clk = ~clk;

// ----------------------------
// TASK: run one test
// ----------------------------
task run_test;
    input [31:0] op_a;
    input [31:0] op_b;
    reg   [31:0] expected;
begin
    // Apply inputs
    a = op_a;
    b = op_b;
    expected = op_a * op_b;

    // Start pulse
    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    // Wait for done
    wait(done);

    @(posedge clk);

    // Print results
    $display("--------------------------------------------------");
    $display("A = %0d, B = %0d", op_a, op_b);
    $display("EXPECTED RESULT = %0d", expected);
    $display("RESULT GOT      = %0d", result);

    if (result === expected)
        $display("STATUS = PASS");
    else
        $display("STATUS = FAIL");

    $display("--------------------------------------------------\n");

    // small delay before next test
    repeat(5) @(posedge clk);
end
endtask

// ----------------------------
// MAIN TEST
// ----------------------------
initial begin
    clk = 0;
    rst = 1;
    start = 0;
    a = 0;
    b = 0;

    // Reset
    #20;
    rst = 0;

    // Run multiple tests
    run_test(7, 5);      // 35
    run_test(10, 3);     // 30
    run_test(15, 2);     // 30
    run_test(8, 8);      // 64

    $display("ALL TESTS COMPLETED");

    #20;
    $finish;
end

endmodule