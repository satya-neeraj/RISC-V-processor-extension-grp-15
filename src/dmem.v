// ============================================================================
// dmem.v  --  128 KB data memory, dual port (port A = CPU, port B = DMA)
//
// Byte write enables on port A (for SB/SH/SW).  Port B only handles full words.
// Address input is byte address in DMEM-local space (0 .. 0x1_FFFF).
// ============================================================================
`timescale 1ns/1ps

module dmem (
    input  wire        clk,

    // Port A (CPU side)
    input  wire        a_en,
    input  wire        a_we,
    input  wire [16:0] a_addr,     // byte addr within DMEM (128KB -> 17 bits)
    input  wire [31:0] a_wdata,
    input  wire [3:0]  a_be,
    output reg  [31:0] a_rdata,

    // Port B (DMA side)
    input  wire        b_en,
    input  wire        b_we,
    input  wire [16:0] b_addr,
    input  wire [31:0] b_wdata,
    output reg  [31:0] b_rdata
);

    // 32K words = 128 KB
    reg [31:0] mem [0:32767];

    initial begin
        $readmemh("dmem.hex", mem);
    end

    wire [14:0] a_widx = a_addr[16:2];
    wire [14:0] b_widx = b_addr[16:2];

    // Port A
    always @(posedge clk) begin
        if (a_en) begin
            if (a_we) begin
                if (a_be[0]) mem[a_widx][ 7: 0] <= a_wdata[ 7: 0];
                if (a_be[1]) mem[a_widx][15: 8] <= a_wdata[15: 8];
                if (a_be[2]) mem[a_widx][23:16] <= a_wdata[23:16];
                if (a_be[3]) mem[a_widx][31:24] <= a_wdata[31:24];
            end
            a_rdata <= mem[a_widx];
        end
    end

    // Port B (DMA, word only)
    always @(posedge clk) begin
        if (b_en) begin
            if (b_we) mem[b_widx] <= b_wdata;
            b_rdata <= mem[b_widx];
        end
    end

endmodule
