// ============================================================================
// imem.v  --  64 KB instruction memory, word-addressed, read-only from CPU
// Initial contents loaded from imem.hex (one 32-bit word per line, hex).
// ============================================================================
`timescale 1ns/1ps

module imem (
    input  wire        clk,
    input  wire [31:0] addr,       // byte address
    output reg  [31:0] rdata
);

    // 16K words = 64 KB
    reg [31:0] mem [0:16383];

    initial begin
        $readmemh("imem.hex", mem);
    end

    // Word-aligned byte address -> word index
    wire [13:0] widx = addr[15:2];

    always @(posedge clk) begin
        rdata <= mem[widx];
    end

endmodule
