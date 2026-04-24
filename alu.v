// ============================================================================
// alu.v  --  single-cycle 32-bit ALU (RV32I subset)
// ============================================================================
`timescale 1ns/1ps
`include "opcode.vh"

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  op,
    output reg  [31:0] y,
    output wire        zero
);

    wire signed [31:0] as = a;
    wire signed [31:0] bs = b;

    always @(*) begin
        case (op)
            `ALU_ADD:  y = a + b;
            `ALU_SUB:  y = a - b;
            `ALU_AND:  y = a & b;
            `ALU_OR:   y = a | b;
            `ALU_XOR:  y = a ^ b;
            `ALU_SLL:  y = a << b[4:0];
            `ALU_SRL:  y = a >> b[4:0];
            `ALU_SRA:  y = as >>> b[4:0];
            `ALU_SLT:  y = (as < bs) ? 32'd1 : 32'd0;
            `ALU_SLTU: y = (a  < b ) ? 32'd1 : 32'd0;
            `ALU_LUI:  y = b;        // imm is already shifted by control_unit
            default:   y = 32'b0;
        endcase
    end

    assign zero = (y == 32'b0);

endmodule
