// ============================================================================
// dma_controller.v  --  Simple memory-to-memory DMA engine.
//
// Programming model (driven by CPU via custom DMA instructions in mem_wb):
//   cfg_src_wr  : load src address  (dma_src <= cfg_data)
//   cfg_dst_wr  : load dst address  (dma_dst <= cfg_data)
//   cfg_len_wr  : load length in words
//   go          : start transfer; busy=1 until done pulses.
//
// During transfer:
//   cycle k+0 : request read at src+4k  -> dmem_b_rdata available next cycle
//   cycle k+1 : request write at dst+4k with latched data
//
// On bus conflict (dma_stall = 1), the DMA controller holds its state
// (does not advance).  This satisfies the "loser only stalls" rule.
// ============================================================================
`timescale 1ns/1ps

module dma_controller (
    input  wire        clk,
    input  wire        rst_n,

    // config writes from CPU
    input  wire        cfg_src_wr,
    input  wire        cfg_dst_wr,
    input  wire        cfg_len_wr,
    input  wire [31:0] cfg_data,

    // go pulse
    input  wire        go,

    // status
    output reg         busy,
    output reg         done,

    // bus-master port (to system_bus)
    output reg         dma_req,
    output reg         dma_we,
    output reg  [31:0] dma_addr,
    output reg  [31:0] dma_wdata,
    input  wire [31:0] dma_rdata,
    input  wire        dma_ready,
    input  wire        dma_stall
);

    // internal config regs
    reg [31:0] src_reg, dst_reg, len_reg;
    reg [31:0] cnt;                 // words transferred
    reg [31:0] read_buf;

    // FSM
    localparam S_IDLE  = 2'd0,
               S_READ  = 2'd1,
               S_WRITE = 2'd2,
               S_DONE  = 2'd3;
    reg [1:0] st;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_reg <= 0; dst_reg <= 0; len_reg <= 0;
            cnt <= 0; read_buf <= 0;
            busy <= 0; done <= 0;
            dma_req <= 0; dma_we <= 0; dma_addr <= 0; dma_wdata <= 0;
            st <= S_IDLE;
        end else begin
            done <= 1'b0;

            // config writes
            if (cfg_src_wr) src_reg <= cfg_data;
            if (cfg_dst_wr) dst_reg <= cfg_data;
            if (cfg_len_wr) len_reg <= cfg_data;

            case (st)
                S_IDLE: begin
                    dma_req <= 1'b0;
                    if (go && !busy) begin
                        busy <= 1'b1;
                        cnt  <= 32'b0;
                        st   <= S_READ;
                    end
                end
                S_READ: begin
                    if (cnt == len_reg) begin
                        st      <= S_DONE;
                        dma_req <= 1'b0;
                    end else begin
                        dma_req  <= 1'b1;
                        dma_we   <= 1'b0;
                        dma_addr <= src_reg + (cnt << 2);
                        if (dma_stall) begin
                            // hold
                        end else if (dma_ready) begin
                            read_buf <= dma_rdata;
                            st       <= S_WRITE;
                        end
                    end
                end
                S_WRITE: begin
                    dma_req   <= 1'b1;
                    dma_we    <= 1'b1;
                    dma_addr  <= dst_reg + (cnt << 2);
                    dma_wdata <= read_buf;
                    if (dma_stall) begin
                        // hold
                    end else if (dma_ready) begin
                        cnt <= cnt + 32'd1;
                        st  <= S_READ;
                    end
                end
                S_DONE: begin
                    busy    <= 1'b0;
                    done    <= 1'b1;
                    dma_req <= 1'b0;
                    dma_we  <= 1'b0;
                    st      <= S_IDLE;
                end
            endcase
        end
    end

endmodule
