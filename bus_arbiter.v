// ============================================================================
// bus_arbiter.v  --  Arbitrates DMEM access between CPU (port A) and DMA.
//
// Priority policy: CPU has higher priority (to keep fetch/writeback moving),
// but if CPU is NOT requesting the bus, DMA gets it.
//
// When both request in the same cycle:
//   - grant_cpu = 1, grant_dma = 0
//   - dma_stall_o = 1   (DMA controller holds state)
// When only DMA requests:
//   - grant_dma = 1
// When only CPU requests:
//   - grant_cpu = 1
// When neither requests: both grants low, no stall.
//
// The "loser-only stall" rule in the spec is implemented by returning
// cpu_stall_o = 0 always (CPU never loses) and dma_stall_o set when DMA
// loses.  If the system ever needs DMA-wins-priority, flip the select.
// ============================================================================
`timescale 1ns/1ps

module bus_arbiter (
    input  wire cpu_req,
    input  wire dma_req,
    output wire grant_cpu,
    output wire grant_dma,
    output wire cpu_stall_o,
    output wire dma_stall_o
);

    assign grant_cpu   = cpu_req;                    // CPU always wins
    assign grant_dma   = dma_req & ~cpu_req;
    assign cpu_stall_o = 1'b0;                       // CPU never loses
    assign dma_stall_o = dma_req & cpu_req;          // DMA stalls only on conflict

endmodule
