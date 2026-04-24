// ============================================================================
// mem_wb_stage.v  --  Memory access + accelerator ops + Writeback.
//
//   Handles, based on inputs from EX/MWB pipeline register:
//     - LW / SW         (via system_bus -> dmem / uart / csr)
//     - MAC.CLR / ACC / RD
//     - CORDIC (asin/acos/atan)
//     - DMA config + go
//     - ALU-class passthrough writeback
//
//   Emits mwb_busy when a multi-cycle op (mac_acc, cordic, dma_go, or stalled
//   LW/SW) is in-flight.  mwb_busy freezes IF/ID and EX upstream.
//
//   On completion of the MAC/CORDIC op, the stage writes back the result
//   to rd via rf_we_out / rf_rd_out / rf_wdata_out.
// ============================================================================
`timescale 1ns/1ps
`include "opcode.vh"

module mem_wb_stage (
    input  wire        clk,
    input  wire        rst_n,

    // inputs from EX/MWB pipeline register
    input  wire [31:0] ex_mwb_pc,
    input  wire [31:0] ex_mwb_instr,
    input  wire [31:0] ex_mwb_alu_out,
    input  wire [31:0] ex_mwb_store_data,
    input  wire [4:0]  ex_mwb_rd,
    input  wire        ex_mwb_reg_we,
    input  wire        ex_mwb_is_load,
    input  wire        ex_mwb_is_store,
    input  wire        ex_mwb_is_mac_clr,
    input  wire        ex_mwb_is_mac_acc,
    input  wire        ex_mwb_is_mac_rd,
    input  wire        ex_mwb_is_cordic,
    input  wire [1:0]  ex_mwb_cordic_mode,
    input  wire        ex_mwb_is_dma_src,
    input  wire        ex_mwb_is_dma_dst,
    input  wire        ex_mwb_is_dma_len,
    input  wire        ex_mwb_is_dma_go,
    input  wire [31:0] ex_mwb_mac_a,
    input  wire [31:0] ex_mwb_mac_b,
    input  wire [31:0] ex_mwb_cordic_in,
    input  wire        ex_mwb_wb_from_mwb,
    input  wire        ex_mwb_valid,

    // ---- system_bus CPU port ----
    output reg         cpu_req,
    output reg         cpu_we,
    output reg  [31:0] cpu_addr,
    output reg  [31:0] cpu_wdata,
    output reg  [3:0]  cpu_be,
    input  wire [31:0] cpu_rdata,
    input  wire        cpu_ready,

    // ---- MAC unit ----
    output reg         mac_op_clr,
    output reg         mac_op_acc,
    output reg  [31:0] mac_a,
    output reg  [31:0] mac_b,
    input  wire [31:0] mac_acc_q16_16,
    input  wire        mac_busy_i,
    input  wire        mac_done_i,

    // ---- CORDIC unit ----
    output reg         cordic_start,
    output reg  [1:0]  cordic_mode,
    output reg  [31:0] cordic_in,
    input  wire [31:0] cordic_result,
    input  wire        cordic_busy_i,
    input  wire        cordic_done_i,

    // ---- DMA config ----
    output reg         dma_cfg_src_wr,
    output reg         dma_cfg_dst_wr,
    output reg         dma_cfg_len_wr,
    output reg  [31:0] dma_cfg_data,
    output reg         dma_go,
    input  wire        dma_busy_i,
    input  wire        dma_done_i,

    // ---- Writeback to register file ----
    output reg         rf_we_out,
    output reg  [4:0]  rf_rd_out,
    output reg  [31:0] rf_wdata_out,

    // ---- Status ----
    output wire        mwb_busy,
    output wire        mem_busy,
    output wire        mwb_is_mc_pending,
    output wire [4:0]  mwb_rd_pending,

    // forwarding support for ALU-class writeback (EX->MWB bypass target)
    output wire        mwb_alu_class_out,
    output wire [4:0]  mwb_rd_o,
    output wire [31:0] mwb_fwd_val_o,
    output wire        mwb_reg_we_o
);

    // ---- FSM for multi-cycle ops in this stage --------------------------
    localparam S_IDLE    = 3'd0,
               S_LDSTORE = 3'd1,
               S_MAC     = 3'd2,
               S_CORDIC  = 3'd3,
               S_DMA     = 3'd4,
               S_WB      = 3'd5;

    reg [2:0] st;
    reg [4:0] pending_rd;
    reg       pending_we;
    reg [31:0] pending_wdata;
    reg        pending_mc;   // pending write is "multi-cycle class" (for hazard_unit)

    // alu-class passthrough immediately writes back same cycle
    wire is_alu_pass = ex_mwb_valid && ex_mwb_reg_we && !ex_mwb_wb_from_mwb &&
                       !ex_mwb_is_load && !ex_mwb_is_mac_rd && !ex_mwb_is_cordic;

    // For forwarding: present the ALU-class writeback info.
    assign mwb_alu_class_out = is_alu_pass;
    assign mwb_rd_o          = ex_mwb_rd;
    assign mwb_fwd_val_o     = ex_mwb_alu_out;
    assign mwb_reg_we_o      = is_alu_pass;

    // default output control
    always @(*) begin
        // memory
        cpu_req   = 1'b0;
        cpu_we    = 1'b0;
        cpu_addr  = 32'b0;
        cpu_wdata = 32'b0;
        cpu_be    = 4'b1111;

        // MAC
        mac_op_clr = 1'b0;
        mac_op_acc = 1'b0;
        mac_a      = 32'b0;
        mac_b      = 32'b0;

        // CORDIC
        cordic_start = 1'b0;
        cordic_mode  = 2'b00;
        cordic_in    = 32'b0;

        // DMA
        dma_cfg_src_wr = 1'b0;
        dma_cfg_dst_wr = 1'b0;
        dma_cfg_len_wr = 1'b0;
        dma_cfg_data   = 32'b0;
        dma_go         = 1'b0;

        case (st)
            S_IDLE: begin
                if (ex_mwb_valid) begin
                    if (ex_mwb_is_load || ex_mwb_is_store) begin
                        cpu_req   = 1'b1;
                        cpu_we    = ex_mwb_is_store;
                        cpu_addr  = ex_mwb_alu_out;
                        cpu_wdata = ex_mwb_store_data;
                        cpu_be    = 4'b1111;
                    end
                    if (ex_mwb_is_mac_clr) begin
                        mac_op_clr = 1'b1;
                    end
                    if (ex_mwb_is_mac_acc) begin
                        mac_op_acc = 1'b1;
                        mac_a      = ex_mwb_mac_a;
                        mac_b      = ex_mwb_mac_b;
                    end
                    if (ex_mwb_is_cordic) begin
                        cordic_start = 1'b1;
                        cordic_mode  = ex_mwb_cordic_mode;
                        cordic_in    = ex_mwb_cordic_in;
                    end
                    if (ex_mwb_is_dma_src) begin
                        dma_cfg_src_wr = 1'b1;
                        dma_cfg_data   = ex_mwb_mac_a;   // rs1 value
                    end
                    if (ex_mwb_is_dma_dst) begin
                        dma_cfg_dst_wr = 1'b1;
                        dma_cfg_data   = ex_mwb_mac_a;
                    end
                    if (ex_mwb_is_dma_len) begin
                        dma_cfg_len_wr = 1'b1;
                        dma_cfg_data   = ex_mwb_mac_a;
                    end
                    if (ex_mwb_is_dma_go) begin
                        dma_go = 1'b1;
                    end
                end
            end
            S_LDSTORE: begin
                // re-drive bus until ready
                cpu_req   = 1'b1;
                cpu_we    = pending_we;     // reuse
                cpu_addr  = pending_wdata;  // address saved here
                cpu_wdata = 32'b0;          // writes completed in S_IDLE
                cpu_be    = 4'b1111;
            end
            S_MAC: begin
                // re-drive acc op? No -- mac_unit has latched a/b; nothing to drive.
            end
            S_CORDIC: begin
                // same
            end
            S_DMA: begin
                // dma_go already pulsed; wait for dma_done_i
            end
            default: ;
        endcase
    end

    // ---- Register writeback (sequential) --------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rf_we_out    <= 1'b0;
            rf_rd_out    <= 5'b0;
            rf_wdata_out <= 32'b0;
            st           <= S_IDLE;
            pending_rd   <= 0;
            pending_we   <= 0;
            pending_wdata <= 0;
            pending_mc   <= 0;
        end else begin
            rf_we_out <= 1'b0;

            case (st)
                S_IDLE: begin
                    if (ex_mwb_valid) begin
                        if (is_alu_pass) begin
                            // instant writeback for ALU/LUI/AUIPC/JAL/JALR/MUL/DIV
                            rf_we_out    <= 1'b1;
                            rf_rd_out    <= ex_mwb_rd;
                            rf_wdata_out <= ex_mwb_alu_out;
                        end
                        if (ex_mwb_is_load) begin
                            // sync-read BRAM: data available next cycle
                            pending_rd <= ex_mwb_rd;
                            pending_we <= 1'b0;
                            pending_mc <= 1'b1;
                            st         <= S_LDSTORE;
                        end else if (ex_mwb_is_store) begin
                            // write happens this cycle via cpu_req; no WB
                            st <= S_IDLE;
                        end else if (ex_mwb_is_mac_rd) begin
                            // combinational read of mac acc
                            rf_we_out    <= 1'b1;
                            rf_rd_out    <= ex_mwb_rd;
                            rf_wdata_out <= mac_acc_q16_16;
                        end else if (ex_mwb_is_mac_acc) begin
                            pending_rd <= 5'b0;      // no writeback
                            pending_we <= 1'b0;
                            pending_mc <= 1'b0;
                            st         <= S_MAC;
                        end else if (ex_mwb_is_cordic) begin
                            pending_rd <= ex_mwb_rd;
                            pending_we <= 1'b1;
                            pending_mc <= 1'b1;
                            st         <= S_CORDIC;
                        end else if (ex_mwb_is_dma_go) begin
                            st <= S_DMA;
                        end
                    end
                end

                S_LDSTORE: begin
                    // after one cycle, cpu_rdata is valid (DMEM sync read)
                    rf_we_out    <= 1'b1;
                    rf_rd_out    <= pending_rd;
                    rf_wdata_out <= cpu_rdata;
                    st           <= S_IDLE;
                    pending_mc   <= 1'b0;
                end

                S_MAC: begin
                    if (mac_done_i) begin
                        // no writeback for mac.acc (use mac.rd to read acc)
                        st <= S_IDLE;
                    end
                end

                S_CORDIC: begin
                    if (cordic_done_i) begin
                        rf_we_out    <= 1'b1;
                        rf_rd_out    <= pending_rd;
                        rf_wdata_out <= cordic_result;
                        st           <= S_IDLE;
                        pending_mc   <= 1'b0;
                    end
                end

                S_DMA: begin
                    if (dma_done_i) begin
                        st <= S_IDLE;
                    end
                end
            endcase
        end
    end

    // ---- Status outputs -------------------------------------------------
    assign mem_busy  = (st == S_LDSTORE);
    assign mwb_busy  = (st != S_IDLE) ||
                       (ex_mwb_valid && (ex_mwb_is_mac_acc || ex_mwb_is_cordic ||
                                         ex_mwb_is_dma_go || ex_mwb_is_load));
    assign mwb_is_mc_pending = pending_mc;
    assign mwb_rd_pending    = pending_rd;

endmodule
