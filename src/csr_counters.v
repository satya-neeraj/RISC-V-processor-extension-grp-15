// ============================================================================
// csr_counters.v  --  Hardware performance counters.
//   9 counters, each 32-bit, read-only via CSR read port.
//   Indexes (matches CSR_BASE offset [5:2]):
//     0  total_cycles
//     1  mul_cycles
//     2  div_cycles
//     3  mac_cycles
//     4  cordic_cycles
//     5  frontend_stall_cycles
//     6  full_stall_cycles
//     7  dma_cycles
//     8  nn_inference_cycles
// ============================================================================
`timescale 1ns/1ps

module csr_counters (
    input  wire        clk,
    input  wire        rst_n,

    // increment-enable signals
    input  wire        run,                  // main enable; counts total
    input  wire        mul_busy,
    input  wire        div_busy,
    input  wire        mac_busy,
    input  wire        cordic_busy,
    input  wire        frontend_stall,       // IF/ID-only stall (EX busy)
    input  wire        full_stall,           // IF/ID + EX stalled (MWB busy)
    input  wire        dma_busy,
    input  wire        nn_infer_active,      // set/cleared by main.c via MMIO

    // read port
    input  wire [3:0]  sel,
    output reg  [31:0] rdata
);

    reg [31:0] total, mul_c, div_c, mac_c, cor_c, fe_st, fu_st, dma_c, nn_c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total <= 0; mul_c <= 0; div_c <= 0; mac_c <= 0; cor_c <= 0;
            fe_st <= 0; fu_st <= 0; dma_c <= 0; nn_c <= 0;
        end else if (run) begin
            total <= total + 1;
            if (mul_busy)       mul_c <= mul_c + 1;
            if (div_busy)       div_c <= div_c + 1;
            if (mac_busy)       mac_c <= mac_c + 1;
            if (cordic_busy)    cor_c <= cor_c + 1;
            if (frontend_stall) fe_st <= fe_st + 1;
            if (full_stall)     fu_st <= fu_st + 1;
            if (dma_busy)       dma_c <= dma_c + 1;
            if (nn_infer_active) nn_c <= nn_c + 1;
        end
    end

    always @(*) begin
        case (sel)
            4'd0: rdata = total;
            4'd1: rdata = mul_c;
            4'd2: rdata = div_c;
            4'd3: rdata = mac_c;
            4'd4: rdata = cor_c;
            4'd5: rdata = fe_st;
            4'd6: rdata = fu_st;
            4'd7: rdata = dma_c;
            4'd8: rdata = nn_c;
            default: rdata = 32'b0;
        endcase
    end

endmodule
