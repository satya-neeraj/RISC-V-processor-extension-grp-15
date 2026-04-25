// tb_dma.v  --  Stand-alone DMA-controller + dmem exercise.
`timescale 1ns/1ps

module tb_dma;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg         cfg_src_wr = 0, cfg_dst_wr = 0, cfg_len_wr = 0;
    reg  [31:0] cfg_data = 0;
    reg         go = 0;
    wire        busy, done;
    wire        dma_req, dma_we;
    wire [31:0] dma_addr, dma_wdata;
    wire [31:0] dma_rdata;
    wire        dma_ready = dma_req;     // no contention
    wire        dma_stall = 1'b0;

    // direct DMEM (pretending there is no CPU contention)
    wire [16:0] dmem_addr = dma_addr[16:0];
    dmem u_dmem (
        .clk(clk),
        .a_en(1'b0), .a_we(1'b0),
        .a_addr(17'b0), .a_wdata(32'b0), .a_be(4'b1111), .a_rdata(),
        .b_en(dma_req), .b_we(dma_we),
        .b_addr(dmem_addr), .b_wdata(dma_wdata), .b_rdata(dma_rdata)
    );

    dma_controller dut(
        .clk(clk), .rst_n(rst_n),
        .cfg_src_wr(cfg_src_wr), .cfg_dst_wr(cfg_dst_wr),
        .cfg_len_wr(cfg_len_wr), .cfg_data(cfg_data),
        .go(go),
        .busy(busy), .done(done),
        .dma_req(dma_req), .dma_we(dma_we),
        .dma_addr(dma_addr), .dma_wdata(dma_wdata),
        .dma_rdata(dma_rdata), .dma_ready(dma_ready),
        .dma_stall(dma_stall)
    );

    initial begin
        #20 rst_n = 1;
        @(posedge clk); cfg_src_wr <= 1; cfg_data <= 32'h0000_0000;
        @(posedge clk); cfg_src_wr <= 0; cfg_dst_wr <= 1; cfg_data <= 32'h0000_0100;
        @(posedge clk); cfg_dst_wr <= 0; cfg_len_wr <= 1; cfg_data <= 32'd8;
        @(posedge clk); cfg_len_wr <= 0;
        @(posedge clk); go <= 1;
        @(posedge clk); go <= 0;
        wait (done);
        @(posedge clk);
        $display("DMA completed 8-word transfer 0x0000->0x0100");
        $finish;
    end
endmodule
