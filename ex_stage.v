// ============================================================================
// ex_stage.v  --  Execute stage.
//
//   Handles:
//     - ALU (single cycle)
//     - LUI / AUIPC / JAL / JALR (single cycle, produce return address in EX)
//     - Branch comparator + branch_target + branch_taken (to IF/ID)
//     - MUL (16-cycle, via mul_unit)
//     - DIV / REM (32-cycle, via div_unit)
//
//   Produces ex_busy when MUL or DIV is in-flight.  While busy, IF/ID is
//   stalled by hazard_unit and bubbles are injected into ex_mem_wb_reg.
//
//   Store/Load/MAC/CORDIC/DMA instructions pass through EX unchanged:
//   EX just computes (rs1 + imm) for addressing, and propagates the class
//   bits + rs2 (store data) to MEM/WB.
// ============================================================================
`timescale 1ns/1ps
`include "opcode.vh"

module ex_stage (
    input  wire        clk,
    input  wire        rst_n,

    // inputs from IF/ID pipeline register
    input  wire [31:0] id_ex_pc,
    input  wire [31:0] id_ex_instr,
    input  wire [31:0] id_ex_a,
    input  wire [31:0] id_ex_b,
    input  wire [31:0] id_ex_imm,
    input  wire [3:0]  id_ex_alu_op,
    input  wire        id_ex_use_imm,
    input  wire        id_ex_reg_we,
    input  wire [4:0]  id_ex_rd,
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,
    input  wire        id_ex_is_alu,
    input  wire        id_ex_is_load,
    input  wire        id_ex_is_store,
    input  wire        id_ex_is_branch,
    input  wire        id_ex_is_jal,
    input  wire        id_ex_is_jalr,
    input  wire        id_ex_is_lui,
    input  wire        id_ex_is_auipc,
    input  wire        id_ex_is_mul,
    input  wire        id_ex_is_div,
    input  wire        id_ex_is_rem,
    input  wire        id_ex_is_mac_clr,
    input  wire        id_ex_is_mac_acc,
    input  wire        id_ex_is_mac_rd,
    input  wire        id_ex_is_cordic,
    input  wire [1:0]  id_ex_cordic_mode,
    input  wire        id_ex_is_dma_src,
    input  wire        id_ex_is_dma_dst,
    input  wire        id_ex_is_dma_len,
    input  wire        id_ex_is_dma_go,
    input  wire        id_ex_wb_from_ex,
    input  wire        id_ex_wb_from_mwb,

    // hazard control
    input  wire        stall_ex,
    input  wire        bubble_ex_mwb,

    // branch outputs back to IF/ID
    output reg         branch_taken,
    output reg  [31:0] branch_target,

    // busy outputs to hazard unit
    output wire        mul_busy,
    output wire        div_busy,
    output wire        mul_div_busy,

    // forwarding hint (EX stage's live ALU result this cycle)
    output wire        ex_alu_class,
    output wire [4:0]  ex_rd_o,
    output wire [31:0] ex_fwd_val,
    output wire        ex_reg_we_o,
    output wire        ex_is_mc_pending,   // a mul/div is in flight for ex_rd

    // EX/MWB pipeline register outputs
    output reg  [31:0] ex_mwb_pc,
    output reg  [31:0] ex_mwb_instr,
    output reg  [31:0] ex_mwb_alu_out,     // addr for LW/SW, or ALU result
    output reg  [31:0] ex_mwb_store_data,  // rs2 value for SW
    output reg  [4:0]  ex_mwb_rd,
    output reg         ex_mwb_reg_we,
    output reg         ex_mwb_is_load,
    output reg         ex_mwb_is_store,
    output reg         ex_mwb_is_mac_clr,
    output reg         ex_mwb_is_mac_acc,
    output reg         ex_mwb_is_mac_rd,
    output reg         ex_mwb_is_cordic,
    output reg  [1:0]  ex_mwb_cordic_mode,
    output reg         ex_mwb_is_dma_src,
    output reg         ex_mwb_is_dma_dst,
    output reg         ex_mwb_is_dma_len,
    output reg         ex_mwb_is_dma_go,
    output reg  [31:0] ex_mwb_mac_a,
    output reg  [31:0] ex_mwb_mac_b,
    output reg  [31:0] ex_mwb_cordic_in,
    output reg         ex_mwb_wb_from_mwb,
    output reg         ex_mwb_valid        // 0 = bubble
);

    // ---- ALU -------------------------------------------------------------
    wire [31:0] alu_b = id_ex_use_imm ? id_ex_imm : id_ex_b;
    wire [31:0] alu_y;
    wire        alu_zero;
    alu u_alu (
        .a (id_ex_is_auipc ? id_ex_pc : id_ex_a),
        .b (alu_b),
        .op(id_ex_alu_op),
        .y (alu_y),
        .zero(alu_zero)
    );

    // ---- Branch decision -------------------------------------------------
    wire [2:0] f3 = id_ex_instr[14:12];
    wire signed [31:0] a_s = id_ex_a;
    wire signed [31:0] b_s = id_ex_b;
    reg  br_cond;
    always @(*) begin
        case (f3)
            `F3_BEQ:  br_cond = (id_ex_a == id_ex_b);
            `F3_BNE:  br_cond = (id_ex_a != id_ex_b);
            `F3_BLT:  br_cond = (a_s    <  b_s);
            `F3_BGE:  br_cond = (a_s    >= b_s);
            `F3_BLTU: br_cond = (id_ex_a <  id_ex_b);
            `F3_BGEU: br_cond = (id_ex_a >= id_ex_b);
            default:  br_cond = 1'b0;
        endcase
    end

    // Branch / jump target
    wire [31:0] br_pc_tgt   = id_ex_pc + id_ex_imm;
    wire [31:0] jal_tgt     = id_ex_pc + id_ex_imm;
    wire [31:0] jalr_tgt    = (id_ex_a + id_ex_imm) & ~32'b1;

    always @(*) begin
        branch_taken  = 1'b0;
        branch_target = 32'b0;
        if (id_ex_is_branch && br_cond) begin
            branch_taken  = 1'b1;
            branch_target = br_pc_tgt;
        end else if (id_ex_is_jal) begin
            branch_taken  = 1'b1;
            branch_target = jal_tgt;
        end else if (id_ex_is_jalr) begin
            branch_taken  = 1'b1;
            branch_target = jalr_tgt;
        end
    end

    // ---- MUL / DIV units -------------------------------------------------
    reg         mul_start_r, div_start_r;
    wire [31:0] mul_res;
    wire        mul_busy_w, mul_done_w;
    wire [31:0] div_q, div_r;
    wire        div_busy_w, div_done_w;

    mul_unit u_mul (
        .clk(clk), .rst_n(rst_n),
        .start(mul_start_r),
        .a(id_ex_a), .b(id_ex_b),
        .result(mul_res),
        .busy(mul_busy_w), .done(mul_done_w)
    );

    div_unit u_div (
        .clk(clk), .rst_n(rst_n),
        .start(div_start_r),
        .a(id_ex_a), .b(id_ex_b),
        .quotient(div_q), .remainder(div_r),
        .busy(div_busy_w), .done(div_done_w)
    );

    assign mul_busy     = mul_busy_w;
    assign div_busy     = div_busy_w;
    assign mul_div_busy = mul_busy_w | div_busy_w;

    // MUL/DIV state machine:
    // - If a new MUL/DIV arrives and no unit is busy, start pulse.
    // - Hold id_ex_rd so we know which reg to write on completion.
    reg [4:0] mc_rd;                 // pending mul/div rd
    reg       mc_is_mul, mc_is_div, mc_is_rem;
    reg       mc_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_start_r <= 0; div_start_r <= 0;
            mc_rd <= 0;
            mc_is_mul <= 0; mc_is_div <= 0; mc_is_rem <= 0;
            mc_pending <= 0;
        end else begin
            mul_start_r <= 0;
            div_start_r <= 0;
            // Launch
            if (!mc_pending && !mul_busy_w && !div_busy_w) begin
                if (id_ex_is_mul) begin
                    mul_start_r <= 1'b1;
                    mc_rd       <= id_ex_rd;
                    mc_is_mul   <= 1'b1;
                    mc_is_div   <= 1'b0;
                    mc_is_rem   <= 1'b0;
                    mc_pending  <= 1'b1;
                end else if (id_ex_is_div) begin
                    div_start_r <= 1'b1;
                    mc_rd       <= id_ex_rd;
                    mc_is_mul   <= 1'b0;
                    mc_is_div   <= 1'b1;
                    mc_is_rem   <= 1'b0;
                    mc_pending  <= 1'b1;
                end else if (id_ex_is_rem) begin
                    div_start_r <= 1'b1;
                    mc_rd       <= id_ex_rd;
                    mc_is_mul   <= 1'b0;
                    mc_is_div   <= 1'b0;
                    mc_is_rem   <= 1'b1;
                    mc_pending  <= 1'b1;
                end
            end
            // Complete: clear pending on done
            if (mul_done_w || div_done_w) mc_pending <= 1'b0;
        end
    end

    // ---- ALU-class forwarding hint --------------------------------------
    wire alu_class_now = id_ex_is_alu | id_ex_is_lui | id_ex_is_auipc |
                         id_ex_is_jal | id_ex_is_jalr;
    wire [31:0] link_val = id_ex_pc + 32'd4;
    wire [31:0] ex_result = (id_ex_is_jal | id_ex_is_jalr) ? link_val : alu_y;

    assign ex_alu_class = alu_class_now;
    assign ex_rd_o      = id_ex_rd;
    assign ex_fwd_val   = ex_result;
    assign ex_reg_we_o  = id_ex_reg_we & alu_class_now;
    assign ex_is_mc_pending = mc_pending;

    // ---- EX/MWB pipeline register ---------------------------------------
    // Three sources can write the EX/MWB register this cycle:
    //   (a) mul_done_w  -> latch MUL result with mc_rd
    //   (b) div_done_w  -> latch DIV/REM result with mc_rd
    //   (c) normal pass-through of an ALU/LOAD/STORE/MAC/CORDIC/DMA instr
    //
    // Localized-stall logic:
    //   if stall_ex      -> freeze ex_mwb_* (MWB finishing prior op)
    //   else if bubble   -> write a NOP (bubble)
    //   else if mul_done -> write MUL result
    //   else if div_done -> write DIV result
    //   else             -> pass through current IF/ID instruction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mwb_pc <= 0; ex_mwb_instr <= `NOP_INSTR;
            ex_mwb_alu_out <= 0; ex_mwb_store_data <= 0;
            ex_mwb_rd <= 0; ex_mwb_reg_we <= 0;
            ex_mwb_is_load <= 0; ex_mwb_is_store <= 0;
            ex_mwb_is_mac_clr <= 0; ex_mwb_is_mac_acc <= 0; ex_mwb_is_mac_rd <= 0;
            ex_mwb_is_cordic <= 0; ex_mwb_cordic_mode <= 0;
            ex_mwb_is_dma_src <= 0; ex_mwb_is_dma_dst <= 0;
            ex_mwb_is_dma_len <= 0; ex_mwb_is_dma_go <= 0;
            ex_mwb_mac_a <= 0; ex_mwb_mac_b <= 0; ex_mwb_cordic_in <= 0;
            ex_mwb_wb_from_mwb <= 0;
            ex_mwb_valid <= 0;
        end else if (stall_ex) begin
            // Freeze -- MWB is busy finishing its own op.  Hold outputs.
        end else if (mul_done_w) begin
            // Latch MUL result as a completed EX-stage instruction
            ex_mwb_pc          <= id_ex_pc;   // (approximate; exact PC held would be better)
            ex_mwb_instr       <= id_ex_instr;
            ex_mwb_alu_out     <= mul_res;
            ex_mwb_store_data  <= 0;
            ex_mwb_rd          <= mc_rd;
            ex_mwb_reg_we      <= 1'b1;
            ex_mwb_is_load     <= 0; ex_mwb_is_store <= 0;
            ex_mwb_is_mac_clr  <= 0; ex_mwb_is_mac_acc <= 0; ex_mwb_is_mac_rd <= 0;
            ex_mwb_is_cordic   <= 0; ex_mwb_cordic_mode <= 0;
            ex_mwb_is_dma_src  <= 0; ex_mwb_is_dma_dst <= 0;
            ex_mwb_is_dma_len  <= 0; ex_mwb_is_dma_go <= 0;
            ex_mwb_wb_from_mwb <= 0;
            ex_mwb_valid       <= 1;
        end else if (div_done_w) begin
            ex_mwb_pc          <= id_ex_pc;
            ex_mwb_instr       <= id_ex_instr;
            ex_mwb_alu_out     <= mc_is_rem ? div_r : div_q;
            ex_mwb_store_data  <= 0;
            ex_mwb_rd          <= mc_rd;
            ex_mwb_reg_we      <= 1'b1;
            ex_mwb_is_load     <= 0; ex_mwb_is_store <= 0;
            ex_mwb_is_mac_clr  <= 0; ex_mwb_is_mac_acc <= 0; ex_mwb_is_mac_rd <= 0;
            ex_mwb_is_cordic   <= 0; ex_mwb_cordic_mode <= 0;
            ex_mwb_is_dma_src  <= 0; ex_mwb_is_dma_dst <= 0;
            ex_mwb_is_dma_len  <= 0; ex_mwb_is_dma_go <= 0;
            ex_mwb_wb_from_mwb <= 0;
            ex_mwb_valid       <= 1;
        end else if (bubble_ex_mwb || id_ex_is_mul || id_ex_is_div || id_ex_is_rem) begin
            // inject bubble while EX is occupied by a multi-cycle op
            ex_mwb_instr       <= `NOP_INSTR;
            ex_mwb_alu_out     <= 0;
            ex_mwb_store_data  <= 0;
            ex_mwb_rd          <= 0;
            ex_mwb_reg_we      <= 0;
            ex_mwb_is_load     <= 0; ex_mwb_is_store <= 0;
            ex_mwb_is_mac_clr  <= 0; ex_mwb_is_mac_acc <= 0; ex_mwb_is_mac_rd <= 0;
            ex_mwb_is_cordic   <= 0; ex_mwb_cordic_mode <= 0;
            ex_mwb_is_dma_src  <= 0; ex_mwb_is_dma_dst <= 0;
            ex_mwb_is_dma_len  <= 0; ex_mwb_is_dma_go <= 0;
            ex_mwb_wb_from_mwb <= 0;
            ex_mwb_valid       <= 0;
        end else begin
            // normal pass-through
            ex_mwb_pc          <= id_ex_pc;
            ex_mwb_instr       <= id_ex_instr;
            ex_mwb_alu_out     <= ex_result;
            ex_mwb_store_data  <= id_ex_b;
            ex_mwb_rd          <= id_ex_rd;
            ex_mwb_reg_we      <= id_ex_reg_we;
            ex_mwb_is_load     <= id_ex_is_load;
            ex_mwb_is_store    <= id_ex_is_store;
            ex_mwb_is_mac_clr  <= id_ex_is_mac_clr;
            ex_mwb_is_mac_acc  <= id_ex_is_mac_acc;
            ex_mwb_is_mac_rd   <= id_ex_is_mac_rd;
            ex_mwb_is_cordic   <= id_ex_is_cordic;
            ex_mwb_cordic_mode <= id_ex_cordic_mode;
            ex_mwb_is_dma_src  <= id_ex_is_dma_src;
            ex_mwb_is_dma_dst  <= id_ex_is_dma_dst;
            ex_mwb_is_dma_len  <= id_ex_is_dma_len;
            ex_mwb_is_dma_go   <= id_ex_is_dma_go;
            ex_mwb_mac_a       <= id_ex_a;
            ex_mwb_mac_b       <= id_ex_b;
            ex_mwb_cordic_in   <= id_ex_a;
            ex_mwb_wb_from_mwb <= id_ex_wb_from_mwb;
            ex_mwb_valid       <= 1;
        end
    end

endmodule
