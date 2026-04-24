// ============================================================================
// register_file.v  --  32 x 32 integer registers, x0 = 0, sync write / async read
// ============================================================================
`timescale 1ns/1ps

module register_file (
    input  wire        clk,
    input  wire        rst_n,

    // Read port 1
    input  wire [4:0]  rs1_addr,
    output wire [31:0] rs1_data,

    // Read port 2
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs2_data,

    // Write port
    input  wire        we,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data
);

    reg [31:0] regs [0:31];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (we && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end

    assign rs1_data = (rs1_addr == 5'd0) ? 32'b0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'b0 : regs[rs2_addr];

endmodule
