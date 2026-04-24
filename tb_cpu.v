// tb_cpu.v  --  Mini CPU smoke test.
//
// Loads a minimal imem.hex (6 instructions) and observes register-file writes
// for 200 cycles.  Use this to confirm end-to-end fetch/decode/EX/MWB flow
// before running the full NN test.
`timescale 1ns/1ps

module tb_cpu;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire [31:0] imem_addr, imem_rdata;
    imem u_imem(.clk(clk), .addr(imem_addr), .rdata(imem_rdata));

    // Simple DMEM stub (no MMIO needed for this smoke test)
    wire        cpu_req, cpu_we;
    wire [31:0] cpu_addr, cpu_wdata;
    wire [3:0]  cpu_be;
    reg  [31:0] cpu_rdata = 0;
    reg         cpu_ready = 1;

    // tie off accelerators
    wire mac_op_clr, mac_op_acc; wire [31:0] mac_a, mac_b;
    wire [31:0] mac_acc; reg mac_busy = 0, mac_done = 0;
    wire cordic_start; wire [1:0] cordic_mode; wire [31:0] cordic_in;
    reg  [31:0] cordic_result = 0; reg cordic_busy = 0, cordic_done = 0;
    wire dma_cfg_src_wr, dma_cfg_dst_wr, dma_cfg_len_wr, dma_go;
    wire [31:0] dma_cfg_data; reg dma_busy = 0, dma_done = 0;
    reg  [31:0] mac_acc_r = 0; assign mac_acc = mac_acc_r;

    cpu_top u_cpu(
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_be(cpu_be),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .mac_op_clr(mac_op_clr), .mac_op_acc(mac_op_acc),
        .mac_a(mac_a), .mac_b(mac_b),
        .mac_acc_q16_16(mac_acc), .mac_busy_i(mac_busy), .mac_done_i(mac_done),
        .cordic_start(cordic_start), .cordic_mode(cordic_mode),
        .cordic_in(cordic_in), .cordic_result(cordic_result),
        .cordic_busy_i(cordic_busy), .cordic_done_i(cordic_done),
        .dma_cfg_src_wr(dma_cfg_src_wr), .dma_cfg_dst_wr(dma_cfg_dst_wr),
        .dma_cfg_len_wr(dma_cfg_len_wr), .dma_cfg_data(dma_cfg_data),
        .dma_go(dma_go), .dma_busy_i(dma_busy), .dma_done_i(dma_done),
        .mul_busy_o(), .div_busy_o(),
        .mac_busy_o(), .cordic_busy_o(), .dma_busy_o(),
        .frontend_stall_o(), .full_stall_o()
    );

    initial begin
        #30 rst_n = 1;
        #2000 $finish;
    end

    initial begin
        $monitor("%0t pc=%h instr=%h", $time, imem_addr, imem_rdata);
    end
endmodule
