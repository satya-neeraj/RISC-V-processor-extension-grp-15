// ============================================================================
// system_bus.v  --  Simple address-decoded fabric for CPU + DMA masters.
//
//   Regions:
//     DMEM   : 0x0001_0000 .. 0x0002_FFFF  (128 KB)
//     UART   : 0x1000_0000 .. 0x1000_0007  (data + status)
//     CSR    : 0x1000_1000 .. 0x1000_1023  (9 counters)
//
//   CPU port (from mem_wb_stage):
//     cpu_req, cpu_we, cpu_addr, cpu_wdata, cpu_be -> response cpu_rdata, cpu_ready
//
//   DMA port (from dma_controller):
//     dma_req, dma_we, dma_addr, dma_wdata -> response dma_rdata, dma_ready
//
//   Downstream:
//     dmem port A (CPU), dmem port B (DMA), uart_tx write, csr read.
// ============================================================================
`timescale 1ns/1ps
`include "opcode.vh"

module system_bus (
    input  wire        clk,
    input  wire        rst_n,

    // ---- CPU master -------------------------------------------------------
    input  wire        cpu_req,
    input  wire        cpu_we,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire [3:0]  cpu_be,
    output reg  [31:0] cpu_rdata,
    output wire        cpu_ready,
    output wire        cpu_stall,    // from arbiter (always 0 in current policy)

    // ---- DMA master -------------------------------------------------------
    input  wire        dma_req,
    input  wire        dma_we,
    input  wire [31:0] dma_addr,
    input  wire [31:0] dma_wdata,
    output wire [31:0] dma_rdata,
    output wire        dma_ready,
    output wire        dma_stall,    // from arbiter

    // ---- DMEM -------------------------------------------------------------
    output wire        dmem_a_en,
    output wire        dmem_a_we,
    output wire [16:0] dmem_a_addr,
    output wire [31:0] dmem_a_wdata,
    output wire [3:0]  dmem_a_be,
    input  wire [31:0] dmem_a_rdata,

    output wire        dmem_b_en,
    output wire        dmem_b_we,
    output wire [16:0] dmem_b_addr,
    output wire [31:0] dmem_b_wdata,
    input  wire [31:0] dmem_b_rdata,

    // ---- UART -------------------------------------------------------------
    output reg         uart_wr,
    output reg  [7:0]  uart_data,
    input  wire        uart_busy,

    // ---- CSR read port ----------------------------------------------------
    output reg  [3:0]  csr_sel,
    input  wire [31:0] csr_rdata
);

    // ---- Address decode ---------------------------------------------------
    wire is_dmem = (cpu_addr >= `DMEM_BASE) && (cpu_addr < `DMEM_END);
    wire is_uart = (cpu_addr == `UART_DATA) || (cpu_addr == `UART_STAT);
    wire is_csr  = (cpu_addr >= `CSR_BASE) && (cpu_addr < (`CSR_BASE + 32'h100));

    // ---- Arbiter ----------------------------------------------------------
    wire cpu_wins_dmem = cpu_req && is_dmem;
    wire grant_cpu, grant_dma;
    bus_arbiter u_arb (
        .cpu_req    (cpu_wins_dmem),
        .dma_req    (dma_req),
        .grant_cpu  (grant_cpu),
        .grant_dma  (grant_dma),
        .cpu_stall_o(cpu_stall),
        .dma_stall_o(dma_stall)
    );

    // ---- DMEM port A (CPU) ------------------------------------------------
    assign dmem_a_en    = grant_cpu;
    assign dmem_a_we    = cpu_we;
    assign dmem_a_addr  = cpu_addr[16:0];
    assign dmem_a_wdata = cpu_wdata;
    assign dmem_a_be    = cpu_be;

    // ---- DMEM port B (DMA) -----------------------------------------------
    assign dmem_b_en    = grant_dma;
    assign dmem_b_we    = dma_we;
    assign dmem_b_addr  = dma_addr[16:0];
    assign dmem_b_wdata = dma_wdata;
    assign dma_rdata    = dmem_b_rdata;
    assign dma_ready    = grant_dma;                    // simple: 1 cycle ok

    // ---- UART write -------------------------------------------------------
    always @(*) begin
        uart_wr   = 1'b0;
        uart_data = 8'b0;
        if (cpu_req && cpu_we && (cpu_addr == `UART_DATA) && !uart_busy) begin
            uart_wr   = 1'b1;
            uart_data = cpu_wdata[7:0];
        end
    end

    // ---- CSR select -------------------------------------------------------
    always @(*) begin
        csr_sel = cpu_addr[5:2];       // 0..15 index
    end

    // ---- Read mux + ready -------------------------------------------------
    reg cpu_ready_r;
    always @(*) begin
        cpu_rdata = 32'b0;
        if (is_dmem) begin
            cpu_rdata = dmem_a_rdata;
        end else if (cpu_addr == `UART_DATA) begin
            cpu_rdata = 32'b0;
        end else if (cpu_addr == `UART_STAT) begin
            cpu_rdata = {31'b0, uart_busy};
        end else if (is_csr) begin
            cpu_rdata = csr_rdata;
        end
    end

    // CPU transaction completes in 1 cycle whenever it is granted (or when
    // accessing UART/CSR which are single-cycle).  A DMEM access that loses
    // arbitration will not happen in the current policy (CPU always wins),
    // but we gate ready on that to be safe.
    assign cpu_ready = cpu_req && ((is_dmem && grant_cpu) || is_uart || is_csr);

endmodule
