// ============================================================================
// forwarding_unit.v  --  Forwarding (bypass) selectors for IF/ID operands.
//
// Allowed:
//   - EX -> EX          : if EX stage produced an ALU-class result this cycle,
//                         forward it to the NEW IF/ID->EX inputs.
//   - EX -> MEM/WB      : writeback path (normal register file write).
//
// NOT allowed (must stall instead):
//   - MUL, DIV, MAC, CORDIC results.  These are handled by hazard_unit
//     issuing a stall until the value is committed to the register file.
//
// Inputs from EX/MWB pipeline regs tell us which registers they will write
// and whether that write is ALU-class (forwardable).
// ============================================================================
`timescale 1ns/1ps

module forwarding_unit (
    // IF/ID decoded register addresses (operands needed)
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,

    // EX stage (what's currently executing, i.e. ex_mem_wb_reg input side)
    input  wire        ex_reg_we,
    input  wire        ex_alu_class,      // ALU / LUI / AUIPC / JAL / JALR
    input  wire [4:0]  ex_rd,
    input  wire [31:0] ex_result,

    // MEM/WB stage (one ahead)
    input  wire        mwb_reg_we,
    input  wire        mwb_alu_class,
    input  wire [4:0]  mwb_rd,
    input  wire [31:0] mwb_result,

    // selectors
    output reg  [1:0]  fwd_sel_a,         // 00 = reg file, 01 = EX, 10 = MWB
    output reg  [1:0]  fwd_sel_b
);

    always @(*) begin
        // rs1
        if (ex_reg_we && ex_alu_class && (ex_rd != 5'd0) && (ex_rd == id_rs1))
            fwd_sel_a = 2'b01;
        else if (mwb_reg_we && mwb_alu_class && (mwb_rd != 5'd0) && (mwb_rd == id_rs1))
            fwd_sel_a = 2'b10;
        else
            fwd_sel_a = 2'b00;

        // rs2
        if (ex_reg_we && ex_alu_class && (ex_rd != 5'd0) && (ex_rd == id_rs2))
            fwd_sel_b = 2'b01;
        else if (mwb_reg_we && mwb_alu_class && (mwb_rd != 5'd0) && (mwb_rd == id_rs2))
            fwd_sel_b = 2'b10;
        else
            fwd_sel_b = 2'b00;
    end

endmodule
