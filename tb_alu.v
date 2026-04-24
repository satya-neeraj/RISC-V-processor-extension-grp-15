// tb_alu.v  --  ALU sanity testbench.  Icarus:  iverilog -o run tb_alu.v ../rtl/alu.v && ./run
`timescale 1ns/1ps
`include "opcode.vh"

module tb_alu;
    reg  [31:0] a, b;
    reg  [3:0]  op;
    wire [31:0] y;
    wire        zero;

    alu dut(.a(a), .b(b), .op(op), .y(y), .zero(zero));

    integer fails = 0;
    task check(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL %0s : got %h, exp %h", name, got, exp);
                fails = fails + 1;
            end else begin
                $display("PASS %0s : %h", name, got);
            end
        end
    endtask

    initial begin
        // ADD
        a = 32'd5;         b = 32'd7;         op = `ALU_ADD;  #1 check("ADD", y, 32'd12);
        // SUB
        a = 32'd10;        b = 32'd3;         op = `ALU_SUB;  #1 check("SUB", y, 32'd7);
        // AND
        a = 32'hFF00FF00;  b = 32'h0FF00FF0;  op = `ALU_AND;  #1 check("AND", y, 32'h0F000F00);
        // OR
        a = 32'h0F0F0F0F;  b = 32'hF0F0F0F0;  op = `ALU_OR;   #1 check("OR",  y, 32'hFFFFFFFF);
        // XOR
        a = 32'hAAAAAAAA;  b = 32'h55555555;  op = `ALU_XOR;  #1 check("XOR", y, 32'hFFFFFFFF);
        // SLL
        a = 32'h1;         b = 32'd4;         op = `ALU_SLL;  #1 check("SLL", y, 32'h10);
        // SRL
        a = 32'hFFFFFFFF;  b = 32'd28;        op = `ALU_SRL;  #1 check("SRL", y, 32'h0000000F);
        // SRA
        a = 32'hFFFFFFFF;  b = 32'd4;         op = `ALU_SRA;  #1 check("SRA", y, 32'hFFFFFFFF);
        // SLT  (signed)
        a = 32'hFFFFFFFE;  b = 32'd1;         op = `ALU_SLT;  #1 check("SLT", y, 32'd1);
        // SLTU (unsigned)
        a = 32'hFFFFFFFE;  b = 32'd1;         op = `ALU_SLTU; #1 check("SLTU",y, 32'd0);
        // LUI
        a = 32'h0;         b = 32'hDEAD1000;  op = `ALU_LUI;  #1 check("LUI", y, 32'hDEAD1000);

        if (fails == 0) $display("ALL ALU TESTS PASSED");
        else            $display("FAILED %0d TESTS", fails);
        $finish;
    end
endmodule
