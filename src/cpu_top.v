// ============================================================================
// cpu_top.v  --  CPU integration: if_id + ex + mem_wb + rf + hazard + forward
// ============================================================================
`timescale 1ns/1ps
`include "opcode.vh"

module cpu_top (
    input  wire        clk,
    input  wire        rst_n,

    // imem
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    // system_bus CPU port
    output wire        cpu_req,
    output wire        cpu_we,
    output wire [31:0] cpu_addr,
    output wire [31:0] cpu_wdata,
    output wire [3:0]  cpu_be,
    input  wire [31:0] cpu_rdata,
    input  wire        cpu_ready,

    // MAC
    output wire        mac_op_clr,
    output wire        mac_op_acc,
    output wire [31:0] mac_a,
    output wire [31:0] mac_b,
    input  wire [31:0] mac_acc_q16_16,
    input  wire        mac_busy_i,
    input  wire        mac_done_i,

    // CORDIC
    output wire        cordic_start,
    output wire [1:0]  cordic_mode,
    output wire [31:0] cordic_in,
    input  wire [31:0] cordic_result,
    input  wire        cordic_busy_i,
    input  wire        cordic_done_i,

    // DMA
    output wire        dma_cfg_src_wr,
    output wire        dma_cfg_dst_wr,
    output wire        dma_cfg_len_wr,
    output wire [31:0] dma_cfg_data,
    output wire        dma_go,
    input  wire        dma_busy_i,
    input  wire        dma_done_i,

    // exposed busy signals for csr_counters
    output wire        mul_busy_o,
    output wire        div_busy_o,
    output wire        mac_busy_o,
    output wire        cordic_busy_o,
    output wire        dma_busy_o,
    output wire        frontend_stall_o,
    output wire        full_stall_o
);

    // --- Register file wires ---
    wire [4:0]  rf_rs1_addr, rf_rs2_addr;
    wire [31:0] rf_rs1_data, rf_rs2_data;
    wire        rf_we;
    wire [4:0]  rf_rd_addr;
    wire [31:0] rf_rd_data;

    register_file u_rf (
        .clk(clk), .rst_n(rst_n),
        .rs1_addr(rf_rs1_addr), .rs1_data(rf_rs1_data),
        .rs2_addr(rf_rs2_addr), .rs2_data(rf_rs2_data),
        .we(rf_we), .rd_addr(rf_rd_addr), .rd_data(rf_rd_data)
    );

    // --- Forwarding wires ---
    wire [1:0] fwd_sel_a, fwd_sel_b;
    wire       ex_alu_class;
    wire [4:0] ex_rd_fwd;
    wire [31:0] ex_fwd_val;
    wire       ex_reg_we_fwd;
    wire       ex_is_mc_pending;

    wire       mwb_alu_class;
    wire [4:0] mwb_rd_fwd;
    wire [31:0] mwb_fwd_val;
    wire       mwb_reg_we_fwd;

    // --- IF/ID output wires ---
    wire [4:0]  id_rs1, id_rs2;
    wire        id_uses_rs1, id_uses_rs2;

    wire [31:0] id_ex_pc, id_ex_instr;
    wire [31:0] id_ex_a, id_ex_b, id_ex_imm;
    wire [3:0]  id_ex_alu_op;
    wire id_ex_use_imm, id_ex_reg_we;
    wire [4:0] id_ex_rd, id_ex_rs1_p, id_ex_rs2_p;
    wire id_ex_is_alu, id_ex_is_load, id_ex_is_store, id_ex_is_branch;
    wire id_ex_is_jal, id_ex_is_jalr, id_ex_is_lui, id_ex_is_auipc;
    wire id_ex_is_mul, id_ex_is_div, id_ex_is_rem;
    wire id_ex_is_mac_clr, id_ex_is_mac_acc, id_ex_is_mac_rd;
    wire id_ex_is_cordic; wire [1:0] id_ex_cordic_mode;
    wire id_ex_is_dma_src, id_ex_is_dma_dst, id_ex_is_dma_len, id_ex_is_dma_go;
    wire id_ex_wb_from_ex, id_ex_wb_from_mwb;

    // --- EX output wires ---
    wire        branch_taken;
    wire [31:0] branch_target;
    wire        mul_busy_w, div_busy_w, mul_div_busy;

    // EX/MWB pipeline bundle
    wire [31:0] ex_mwb_pc, ex_mwb_instr;
    wire [31:0] ex_mwb_alu_out, ex_mwb_store_data;
    wire [4:0]  ex_mwb_rd;
    wire        ex_mwb_reg_we;
    wire        ex_mwb_is_load, ex_mwb_is_store;
    wire        ex_mwb_is_mac_clr, ex_mwb_is_mac_acc, ex_mwb_is_mac_rd;
    wire        ex_mwb_is_cordic; wire [1:0] ex_mwb_cordic_mode;
    wire        ex_mwb_is_dma_src, ex_mwb_is_dma_dst, ex_mwb_is_dma_len, ex_mwb_is_dma_go;
    wire [31:0] ex_mwb_mac_a, ex_mwb_mac_b, ex_mwb_cordic_in;
    wire        ex_mwb_wb_from_mwb, ex_mwb_valid;

    // --- MWB outputs ---
    wire mwb_busy_w, mem_busy_w;
    wire mwb_is_mc_pending;
    wire [4:0] mwb_rd_pending;

    // --- Hazard wires ---
    wire stall_if_id, stall_ex, bubble_ex_mwb;

    // ----------------------------- Hazard unit ----------------------------
    hazard_unit u_haz (
        .ex_busy       (mul_div_busy),
        .ex_done       (1'b0),                // not used internally
        .mwb_busy      (mwb_busy_w),
        .ex_is_mc      (ex_is_mc_pending),
        .ex_rd         (id_ex_rd),            // approximate: the rd being awaited
        .mwb_is_mc     (mwb_is_mc_pending),
        .mwb_rd        (mwb_rd_pending),
        .id_rs1        (id_rs1),
        .id_rs2        (id_rs2),
        .id_uses_rs1   (id_uses_rs1),
        .id_uses_rs2   (id_uses_rs2),
        .stall_if_id   (stall_if_id),
        .stall_ex      (stall_ex),
        .bubble_ex_mwb (bubble_ex_mwb)
    );

    // ------------------------------ Forwarding ----------------------------
    forwarding_unit u_fwd (
        .id_rs1       (id_rs1),
        .id_rs2       (id_rs2),
        .ex_reg_we    (ex_reg_we_fwd),
        .ex_alu_class (ex_alu_class),
        .ex_rd        (ex_rd_fwd),
        .ex_result    (ex_fwd_val),
        .mwb_reg_we   (mwb_reg_we_fwd),
        .mwb_alu_class(mwb_alu_class),
        .mwb_rd       (mwb_rd_fwd),
        .mwb_result   (mwb_fwd_val),
        .fwd_sel_a    (fwd_sel_a),
        .fwd_sel_b    (fwd_sel_b)
    );

    // ------------------------------ IF/ID ---------------------------------
    if_id_stage u_ifid (
        .clk(clk), .rst_n(rst_n),
        .stall_if_id(stall_if_id),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .rf_rs1_addr(rf_rs1_addr), .rf_rs2_addr(rf_rs2_addr),
        .rf_rs1_data(rf_rs1_data), .rf_rs2_data(rf_rs2_data),
        .fwd_sel_a(fwd_sel_a), .fwd_sel_b(fwd_sel_b),
        .ex_fwd_val(ex_fwd_val), .mwb_fwd_val(mwb_fwd_val),
        .id_ex_pc(id_ex_pc), .id_ex_instr(id_ex_instr),
        .id_ex_a(id_ex_a), .id_ex_b(id_ex_b), .id_ex_imm(id_ex_imm),
        .id_ex_alu_op(id_ex_alu_op), .id_ex_use_imm(id_ex_use_imm),
        .id_ex_reg_we(id_ex_reg_we),
        .id_ex_rd(id_ex_rd), .id_ex_rs1(id_ex_rs1_p), .id_ex_rs2(id_ex_rs2_p),
        .id_ex_is_alu(id_ex_is_alu), .id_ex_is_load(id_ex_is_load),
        .id_ex_is_store(id_ex_is_store), .id_ex_is_branch(id_ex_is_branch),
        .id_ex_is_jal(id_ex_is_jal), .id_ex_is_jalr(id_ex_is_jalr),
        .id_ex_is_lui(id_ex_is_lui), .id_ex_is_auipc(id_ex_is_auipc),
        .id_ex_is_mul(id_ex_is_mul), .id_ex_is_div(id_ex_is_div),
        .id_ex_is_rem(id_ex_is_rem),
        .id_ex_is_mac_clr(id_ex_is_mac_clr), .id_ex_is_mac_acc(id_ex_is_mac_acc),
        .id_ex_is_mac_rd(id_ex_is_mac_rd),
        .id_ex_is_cordic(id_ex_is_cordic), .id_ex_cordic_mode(id_ex_cordic_mode),
        .id_ex_is_dma_src(id_ex_is_dma_src), .id_ex_is_dma_dst(id_ex_is_dma_dst),
        .id_ex_is_dma_len(id_ex_is_dma_len), .id_ex_is_dma_go(id_ex_is_dma_go),
        .id_ex_wb_from_ex(id_ex_wb_from_ex), .id_ex_wb_from_mwb(id_ex_wb_from_mwb),
        .id_rs1_out(id_rs1), .id_rs2_out(id_rs2),
        .id_uses_rs1(id_uses_rs1), .id_uses_rs2(id_uses_rs2)
    );

    // --------------------------------- EX ---------------------------------
    ex_stage u_ex (
        .clk(clk), .rst_n(rst_n),
        .id_ex_pc(id_ex_pc), .id_ex_instr(id_ex_instr),
        .id_ex_a(id_ex_a), .id_ex_b(id_ex_b), .id_ex_imm(id_ex_imm),
        .id_ex_alu_op(id_ex_alu_op), .id_ex_use_imm(id_ex_use_imm),
        .id_ex_reg_we(id_ex_reg_we),
        .id_ex_rd(id_ex_rd), .id_ex_rs1(id_ex_rs1_p), .id_ex_rs2(id_ex_rs2_p),
        .id_ex_is_alu(id_ex_is_alu), .id_ex_is_load(id_ex_is_load),
        .id_ex_is_store(id_ex_is_store), .id_ex_is_branch(id_ex_is_branch),
        .id_ex_is_jal(id_ex_is_jal), .id_ex_is_jalr(id_ex_is_jalr),
        .id_ex_is_lui(id_ex_is_lui), .id_ex_is_auipc(id_ex_is_auipc),
        .id_ex_is_mul(id_ex_is_mul), .id_ex_is_div(id_ex_is_div),
        .id_ex_is_rem(id_ex_is_rem),
        .id_ex_is_mac_clr(id_ex_is_mac_clr), .id_ex_is_mac_acc(id_ex_is_mac_acc),
        .id_ex_is_mac_rd(id_ex_is_mac_rd),
        .id_ex_is_cordic(id_ex_is_cordic), .id_ex_cordic_mode(id_ex_cordic_mode),
        .id_ex_is_dma_src(id_ex_is_dma_src), .id_ex_is_dma_dst(id_ex_is_dma_dst),
        .id_ex_is_dma_len(id_ex_is_dma_len), .id_ex_is_dma_go(id_ex_is_dma_go),
        .id_ex_wb_from_ex(id_ex_wb_from_ex), .id_ex_wb_from_mwb(id_ex_wb_from_mwb),
        .stall_ex(stall_ex),
        .bubble_ex_mwb(bubble_ex_mwb),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .mul_busy(mul_busy_w), .div_busy(div_busy_w),
        .mul_div_busy(mul_div_busy),
        .ex_alu_class(ex_alu_class),
        .ex_rd_o(ex_rd_fwd),
        .ex_fwd_val(ex_fwd_val),
        .ex_reg_we_o(ex_reg_we_fwd),
        .ex_is_mc_pending(ex_is_mc_pending),
        .ex_mwb_pc(ex_mwb_pc), .ex_mwb_instr(ex_mwb_instr),
        .ex_mwb_alu_out(ex_mwb_alu_out), .ex_mwb_store_data(ex_mwb_store_data),
        .ex_mwb_rd(ex_mwb_rd), .ex_mwb_reg_we(ex_mwb_reg_we),
        .ex_mwb_is_load(ex_mwb_is_load), .ex_mwb_is_store(ex_mwb_is_store),
        .ex_mwb_is_mac_clr(ex_mwb_is_mac_clr), .ex_mwb_is_mac_acc(ex_mwb_is_mac_acc),
        .ex_mwb_is_mac_rd(ex_mwb_is_mac_rd),
        .ex_mwb_is_cordic(ex_mwb_is_cordic), .ex_mwb_cordic_mode(ex_mwb_cordic_mode),
        .ex_mwb_is_dma_src(ex_mwb_is_dma_src), .ex_mwb_is_dma_dst(ex_mwb_is_dma_dst),
        .ex_mwb_is_dma_len(ex_mwb_is_dma_len), .ex_mwb_is_dma_go(ex_mwb_is_dma_go),
        .ex_mwb_mac_a(ex_mwb_mac_a), .ex_mwb_mac_b(ex_mwb_mac_b),
        .ex_mwb_cordic_in(ex_mwb_cordic_in),
        .ex_mwb_wb_from_mwb(ex_mwb_wb_from_mwb),
        .ex_mwb_valid(ex_mwb_valid)
    );

    // ------------------------------- MEM/WB -------------------------------
    mem_wb_stage u_mwb (
        .clk(clk), .rst_n(rst_n),
        .ex_mwb_pc(ex_mwb_pc), .ex_mwb_instr(ex_mwb_instr),
        .ex_mwb_alu_out(ex_mwb_alu_out), .ex_mwb_store_data(ex_mwb_store_data),
        .ex_mwb_rd(ex_mwb_rd), .ex_mwb_reg_we(ex_mwb_reg_we),
        .ex_mwb_is_load(ex_mwb_is_load), .ex_mwb_is_store(ex_mwb_is_store),
        .ex_mwb_is_mac_clr(ex_mwb_is_mac_clr), .ex_mwb_is_mac_acc(ex_mwb_is_mac_acc),
        .ex_mwb_is_mac_rd(ex_mwb_is_mac_rd),
        .ex_mwb_is_cordic(ex_mwb_is_cordic), .ex_mwb_cordic_mode(ex_mwb_cordic_mode),
        .ex_mwb_is_dma_src(ex_mwb_is_dma_src), .ex_mwb_is_dma_dst(ex_mwb_is_dma_dst),
        .ex_mwb_is_dma_len(ex_mwb_is_dma_len), .ex_mwb_is_dma_go(ex_mwb_is_dma_go),
        .ex_mwb_mac_a(ex_mwb_mac_a), .ex_mwb_mac_b(ex_mwb_mac_b),
        .ex_mwb_cordic_in(ex_mwb_cordic_in),
        .ex_mwb_wb_from_mwb(ex_mwb_wb_from_mwb),
        .ex_mwb_valid(ex_mwb_valid),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_be(cpu_be),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .mac_op_clr(mac_op_clr), .mac_op_acc(mac_op_acc),
        .mac_a(mac_a), .mac_b(mac_b),
        .mac_acc_q16_16(mac_acc_q16_16),
        .mac_busy_i(mac_busy_i), .mac_done_i(mac_done_i),
        .cordic_start(cordic_start), .cordic_mode(cordic_mode),
        .cordic_in(cordic_in),
        .cordic_result(cordic_result),
        .cordic_busy_i(cordic_busy_i), .cordic_done_i(cordic_done_i),
        .dma_cfg_src_wr(dma_cfg_src_wr), .dma_cfg_dst_wr(dma_cfg_dst_wr),
        .dma_cfg_len_wr(dma_cfg_len_wr), .dma_cfg_data(dma_cfg_data),
        .dma_go(dma_go),
        .dma_busy_i(dma_busy_i), .dma_done_i(dma_done_i),
        .rf_we_out(rf_we), .rf_rd_out(rf_rd_addr), .rf_wdata_out(rf_rd_data),
        .mwb_busy(mwb_busy_w),
        .mem_busy(mem_busy_w),
        .mwb_is_mc_pending(mwb_is_mc_pending),
        .mwb_rd_pending(mwb_rd_pending),
        .mwb_alu_class_out(mwb_alu_class),
        .mwb_rd_o(mwb_rd_fwd),
        .mwb_fwd_val_o(mwb_fwd_val),
        .mwb_reg_we_o(mwb_reg_we_fwd)
    );

    // ---- Exposed busy signals to csr_counters ----
    assign mul_busy_o       = mul_busy_w;
    assign div_busy_o       = div_busy_w;
    assign mac_busy_o       = mac_busy_i;
    assign cordic_busy_o    = cordic_busy_i;
    assign dma_busy_o       = dma_busy_i;
    assign frontend_stall_o = stall_if_id & ~stall_ex;   // only IF/ID stalls
    assign full_stall_o     = stall_if_id &  stall_ex;   // IF/ID + EX stall

endmodule
