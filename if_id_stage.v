// ============================================================================
// if_id_stage.v  --  Combined Fetch + Decode + Register-Read stage.
//
// Architectural role:
//   - owns the PC
//   - issues instruction fetch to imem
//   - decodes the fetched instruction via control_unit
//   - reads rs1/rs2 from the register file
//   - applies forwarding (if enabled by forwarding_unit)
//   - presents a packaged "issue" bundle to the EX stage via id_ex_*
//
// Stall semantics:
//   - When stall_if_id==1, PC and latched instr DO NOT advance.
//     Outputs continue to present the currently-latched instruction.
//   - When branch_taken==1, PC is redirected to branch_target and the
//     currently-fetched instruction is squashed (replaced by NOP downstream).
// ============================================================================
`timescale 1ns/1ps
`include "opcode.vh"

module if_id_stage (
    input  wire        clk,
    input  wire        rst_n,

    // control from hazard / branch
    input  wire        stall_if_id,
    input  wire        branch_taken,
    input  wire [31:0] branch_target,

    // imem interface
    output reg  [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    // register file (external)
    output wire [4:0]  rf_rs1_addr,
    output wire [4:0]  rf_rs2_addr,
    input  wire [31:0] rf_rs1_data,
    input  wire [31:0] rf_rs2_data,

    // forwarding inputs
    input  wire [1:0]  fwd_sel_a,
    input  wire [1:0]  fwd_sel_b,
    input  wire [31:0] ex_fwd_val,
    input  wire [31:0] mwb_fwd_val,

    // outputs to EX (latched)
    output reg  [31:0] id_ex_pc,
    output reg  [31:0] id_ex_instr,
    output reg  [31:0] id_ex_a,
    output reg  [31:0] id_ex_b,
    output reg  [31:0] id_ex_imm,
    output reg  [3:0]  id_ex_alu_op,
    output reg         id_ex_use_imm,
    output reg         id_ex_reg_we,
    output reg  [4:0]  id_ex_rd,
    output reg  [4:0]  id_ex_rs1,
    output reg  [4:0]  id_ex_rs2,
    // class flags (propagated)
    output reg         id_ex_is_alu,
    output reg         id_ex_is_load,
    output reg         id_ex_is_store,
    output reg         id_ex_is_branch,
    output reg         id_ex_is_jal,
    output reg         id_ex_is_jalr,
    output reg         id_ex_is_lui,
    output reg         id_ex_is_auipc,
    output reg         id_ex_is_mul,
    output reg         id_ex_is_div,
    output reg         id_ex_is_rem,
    output reg         id_ex_is_mac_clr,
    output reg         id_ex_is_mac_acc,
    output reg         id_ex_is_mac_rd,
    output reg         id_ex_is_cordic,
    output reg  [1:0]  id_ex_cordic_mode,
    output reg         id_ex_is_dma_src,
    output reg         id_ex_is_dma_dst,
    output reg         id_ex_is_dma_len,
    output reg         id_ex_is_dma_go,
    output reg         id_ex_wb_from_ex,
    output reg         id_ex_wb_from_mwb,

    // to hazard_unit
    output wire [4:0]  id_rs1_out,
    output wire [4:0]  id_rs2_out,
    output wire        id_uses_rs1,
    output wire        id_uses_rs2
);

    // ---- Program Counter --------------------------------------------------
    reg [31:0] pc;
    wire [31:0] pc_next = branch_taken ? branch_target :
                          stall_if_id  ? pc            :
                                         pc + 32'd4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc <= 32'h0000_0000;
        else        pc <= pc_next;
    end

    always @(*) imem_addr = pc;       // combinational address; imem latches

    // ---- Fetched instruction register ------------------------------------
    // imem is a sync-read BRAM.  After reset, pc=0 is presented; next cycle
    // imem_rdata has instr[0].  To keep the 3-stage model, we treat imem_rdata
    // itself as the instruction in IF/ID this cycle (combined IF+ID).
    wire [31:0] instr_raw = imem_rdata;

    // Squash on branch (replace with NOP downstream)
    wire [31:0] instr = branch_taken ? `NOP_INSTR : instr_raw;

    // ---- Decode ----------------------------------------------------------
    wire is_alu, is_load, is_store, is_branch, is_jal, is_jalr, is_lui, is_auipc;
    wire is_mul, is_div, is_rem;
    wire is_mac_clr, is_mac_acc, is_mac_rd;
    wire is_cordic;
    wire [1:0] cordic_mode;
    wire is_dma_src, is_dma_dst, is_dma_len, is_dma_go;
    wire [4:0] d_rs1, d_rs2, d_rd;
    wire [31:0] d_imm;
    wire [3:0] d_alu_op;
    wire d_reg_we, d_use_imm;
    wire d_wb_from_ex, d_wb_from_mwb;

    control_unit u_ctrl (
        .instr       (instr),
        .is_alu      (is_alu),
        .is_load     (is_load),
        .is_store    (is_store),
        .is_branch   (is_branch),
        .is_jal      (is_jal),
        .is_jalr     (is_jalr),
        .is_lui      (is_lui),
        .is_auipc    (is_auipc),
        .is_mul      (is_mul),
        .is_div      (is_div),
        .is_rem      (is_rem),
        .is_mac_clr  (is_mac_clr),
        .is_mac_acc  (is_mac_acc),
        .is_mac_rd   (is_mac_rd),
        .is_cordic   (is_cordic),
        .cordic_mode (cordic_mode),
        .is_dma_src  (is_dma_src),
        .is_dma_dst  (is_dma_dst),
        .is_dma_len  (is_dma_len),
        .is_dma_go   (is_dma_go),
        .rs1_addr    (d_rs1),
        .rs2_addr    (d_rs2),
        .rd_addr     (d_rd),
        .imm         (d_imm),
        .alu_op      (d_alu_op),
        .reg_we      (d_reg_we),
        .use_imm     (d_use_imm),
        .wb_from_ex  (d_wb_from_ex),
        .wb_from_mwb (d_wb_from_mwb)
    );

    assign rf_rs1_addr = d_rs1;
    assign rf_rs2_addr = d_rs2;

    // tell hazard_unit which regs we read
    assign id_rs1_out   = d_rs1;
    assign id_rs2_out   = d_rs2;
    assign id_uses_rs1  = is_alu | is_load | is_store | is_branch | is_jalr |
                          is_mul | is_div | is_rem | is_mac_acc | is_cordic |
                          is_dma_src | is_dma_dst | is_dma_len | is_dma_go;
    assign id_uses_rs2  = (is_alu & ~d_use_imm) | is_store | is_branch |
                          is_mul | is_div | is_rem | is_mac_acc;

    // ---- Forwarding mux --------------------------------------------------
    reg [31:0] a_forwarded, b_forwarded;
    always @(*) begin
        case (fwd_sel_a)
            2'b01: a_forwarded = ex_fwd_val;
            2'b10: a_forwarded = mwb_fwd_val;
            default: a_forwarded = rf_rs1_data;
        endcase
        case (fwd_sel_b)
            2'b01: b_forwarded = ex_fwd_val;
            2'b10: b_forwarded = mwb_fwd_val;
            default: b_forwarded = rf_rs2_data;
        endcase
    end

    // ---- ID/EX pipeline register ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_pc <= 0; id_ex_instr <= `NOP_INSTR;
            id_ex_a <= 0; id_ex_b <= 0; id_ex_imm <= 0;
            id_ex_alu_op <= 0; id_ex_use_imm <= 0;
            id_ex_reg_we <= 0; id_ex_rd <= 0;
            id_ex_rs1 <= 0; id_ex_rs2 <= 0;
            id_ex_is_alu <= 0; id_ex_is_load <= 0; id_ex_is_store <= 0;
            id_ex_is_branch <= 0; id_ex_is_jal <= 0; id_ex_is_jalr <= 0;
            id_ex_is_lui <= 0; id_ex_is_auipc <= 0;
            id_ex_is_mul <= 0; id_ex_is_div <= 0; id_ex_is_rem <= 0;
            id_ex_is_mac_clr <= 0; id_ex_is_mac_acc <= 0; id_ex_is_mac_rd <= 0;
            id_ex_is_cordic <= 0; id_ex_cordic_mode <= 0;
            id_ex_is_dma_src <= 0; id_ex_is_dma_dst <= 0;
            id_ex_is_dma_len <= 0; id_ex_is_dma_go <= 0;
            id_ex_wb_from_ex <= 0; id_ex_wb_from_mwb <= 0;
        end else if (!stall_if_id) begin
            id_ex_pc          <= pc;
            id_ex_instr       <= instr;
            id_ex_a           <= a_forwarded;
            id_ex_b           <= b_forwarded;
            id_ex_imm         <= d_imm;
            id_ex_alu_op      <= d_alu_op;
            id_ex_use_imm     <= d_use_imm;
            id_ex_reg_we      <= d_reg_we;
            id_ex_rd          <= d_rd;
            id_ex_rs1         <= d_rs1;
            id_ex_rs2         <= d_rs2;
            id_ex_is_alu      <= is_alu;
            id_ex_is_load     <= is_load;
            id_ex_is_store    <= is_store;
            id_ex_is_branch   <= is_branch;
            id_ex_is_jal      <= is_jal;
            id_ex_is_jalr     <= is_jalr;
            id_ex_is_lui      <= is_lui;
            id_ex_is_auipc    <= is_auipc;
            id_ex_is_mul      <= is_mul;
            id_ex_is_div      <= is_div;
            id_ex_is_rem      <= is_rem;
            id_ex_is_mac_clr  <= is_mac_clr;
            id_ex_is_mac_acc  <= is_mac_acc;
            id_ex_is_mac_rd   <= is_mac_rd;
            id_ex_is_cordic   <= is_cordic;
            id_ex_cordic_mode <= cordic_mode;
            id_ex_is_dma_src  <= is_dma_src;
            id_ex_is_dma_dst  <= is_dma_dst;
            id_ex_is_dma_len  <= is_dma_len;
            id_ex_is_dma_go   <= is_dma_go;
            id_ex_wb_from_ex  <= d_wb_from_ex;
            id_ex_wb_from_mwb <= d_wb_from_mwb;
        end
        // if stall_if_id, hold prior values
    end

endmodule
