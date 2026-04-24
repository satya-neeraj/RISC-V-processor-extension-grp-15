// ============================================================================
// hazard_unit.v  --  Localized-stall hazard detection.
//
// Produces three control outputs used by cpu_top:
//
//   stall_if_id    -- freeze PC and IF/ID pipeline register
//   stall_ex       -- freeze EX pipeline register (blocks new instr entering MWB)
//   bubble_ex_mwb  -- inject NOP into ex_mem_wb_reg (so MWB sees a bubble)
//
// Stall sources (in priority order):
//
//   (1) MEM/WB busy  (MAC/CORDIC/DMA/LW/SW not yet complete)
//        -> stall_if_id = 1
//        -> stall_ex    = 1        (ex_mem_wb_reg is FROZEN, no new bubble)
//        -> bubble_ex_mwb = 0
//
//   (2) EX busy      (MUL/DIV in progress)
//        -> stall_if_id   = 1
//        -> stall_ex      = 0     (EX stays in-place by virtue of being busy)
//        -> bubble_ex_mwb = 1 for cycles 1..N-1; on mul_done/div_done, 0 so
//                              the real result latches.
//
//   (3) RAW on multi-cycle result (upcoming instr reads rd of pending MUL/DIV/MAC/CORDIC)
//        -> stall_if_id   = 1
//        -> stall_ex      = 0
//        -> bubble_ex_mwb = 0      (we just stall IF/ID until the value is committed)
//
//   (4) Branch taken -> IF/ID flush (handled in cpu_top, not here)
// ============================================================================
`timescale 1ns/1ps

module hazard_unit (
    // EX state
    input  wire        ex_busy,          // mul_busy | div_busy
    input  wire        ex_done,          // mul_done | div_done (1-cycle pulse)

    // MWB state
    input  wire        mwb_busy,         // mac_busy | cordic_busy | dma_busy | mem_busy

    // Pending writes (for RAW-on-multi-cycle detection)
    input  wire        ex_is_mc,         // EX stage holds a mul/div
    input  wire [4:0]  ex_rd,
    input  wire        mwb_is_mc,        // MWB stage holds a mac-rd/cordic/load
    input  wire [4:0]  mwb_rd,

    // IF/ID operands
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire        id_uses_rs1,
    input  wire        id_uses_rs2,

    // outputs
    output wire        stall_if_id,
    output wire        stall_ex,
    output wire        bubble_ex_mwb
);

    // RAW hazard: in-flight multi-cycle writer vs current decode
    wire raw_ex  =  ex_is_mc  && (ex_rd  != 5'd0) &&
                   ((id_uses_rs1 && (id_rs1 == ex_rd )) ||
                    (id_uses_rs2 && (id_rs2 == ex_rd )));
    wire raw_mwb =  mwb_is_mc && (mwb_rd != 5'd0) &&
                   ((id_uses_rs1 && (id_rs1 == mwb_rd)) ||
                    (id_uses_rs2 && (id_rs2 == mwb_rd)));

    // Priority: MWB-busy  >  EX-busy  >  RAW
    assign stall_if_id   = mwb_busy | ex_busy | raw_ex | raw_mwb;
    assign stall_ex      = mwb_busy;
    assign bubble_ex_mwb = ex_busy & ~ex_done;   // bubbles while EX churning

endmodule
