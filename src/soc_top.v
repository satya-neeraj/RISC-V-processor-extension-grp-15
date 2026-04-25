//============================================================================
`timescale 1ns/1ps
`include "opcode.vh"

module soc_top (
    input  wire        clk_100mhz,
    input  wire        btn_cpu_resetn,
    output wire        RsTx,
    output wire [15:0] led
);

    // ---- Clock / reset ---------------------------------------------------
    wire clk, rst_n;
    clk_rst u_clkrst (
        .clk_in     (clk_100mhz),
        .btn_resetn (btn_cpu_resetn),
        .clk_out    (clk),
        .rst_n_sync (rst_n)
    );

    // ---- CPU <-> imem ----------------------------------------------------
    wire [31:0] imem_addr, imem_rdata;
    imem u_imem (.clk(clk), .addr(imem_addr), .rdata(imem_rdata));

    // ---- CPU <-> bus -----------------------------------------------------
    wire        cpu_req, cpu_we;
    wire [31:0] cpu_addr, cpu_wdata;
    wire [3:0]  cpu_be;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;

    // ---- Accelerator wires ----------------------------------------------
    wire        mac_op_clr, mac_op_acc;
    wire [31:0] mac_a, mac_b;
    wire [31:0] mac_acc_q16_16;
    wire        mac_busy, mac_done;

    wire        cordic_start;
    wire [1:0]  cordic_mode;
    wire [31:0] cordic_in;
    wire [31:0] cordic_result;
    wire        cordic_busy, cordic_done;

    wire        dma_cfg_src_wr, dma_cfg_dst_wr, dma_cfg_len_wr;
    wire [31:0] dma_cfg_data;
    wire        dma_go;
    wire        dma_busy, dma_done;

    wire        mul_busy, div_busy;
    wire        frontend_stall, full_stall;

    // ---- CPU -------------------------------------------------------------
    cpu_top u_cpu (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_be(cpu_be),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .mac_op_clr(mac_op_clr), .mac_op_acc(mac_op_acc),
        .mac_a(mac_a), .mac_b(mac_b),
        .mac_acc_q16_16(mac_acc_q16_16),
        .mac_busy_i(mac_busy), .mac_done_i(mac_done),
        .cordic_start(cordic_start), .cordic_mode(cordic_mode),
        .cordic_in(cordic_in),
        .cordic_result(cordic_result),
        .cordic_busy_i(cordic_busy), .cordic_done_i(cordic_done),
        .dma_cfg_src_wr(dma_cfg_src_wr), .dma_cfg_dst_wr(dma_cfg_dst_wr),
        .dma_cfg_len_wr(dma_cfg_len_wr), .dma_cfg_data(dma_cfg_data),
        .dma_go(dma_go),
        .dma_busy_i(dma_busy), .dma_done_i(dma_done),
        .mul_busy_o(mul_busy), .div_busy_o(div_busy),
        .mac_busy_o(),   // same as mac_busy
        .cordic_busy_o(),
        .dma_busy_o(),
        .frontend_stall_o(frontend_stall), .full_stall_o(full_stall)
    );

    // ---- MAC -------------------------------------------------------------
    mac_unit u_mac (
        .clk(clk), .rst_n(rst_n),
        .op_clr(mac_op_clr), .op_acc(mac_op_acc),
        .a_q16_16(mac_a), .b_q16_16(mac_b),
        .acc_q16_16(mac_acc_q16_16),
        .busy(mac_busy), .done(mac_done)
    );

    // ---- CORDIC ----------------------------------------------------------
    cordic_unit u_cordic (
        .clk(clk), .rst_n(rst_n),
        .start(cordic_start), .mode(cordic_mode), .x_in(cordic_in),
        .result(cordic_result),
        .busy(cordic_busy), .done(cordic_done)
    );

    // ---- DMA controller --------------------------------------------------
    wire        dma_req, dma_we;
    wire [31:0] dma_addr, dma_wdata;
    wire [31:0] dma_rdata;
    wire        dma_ready, dma_stall;

    dma_controller u_dma (
        .clk(clk), .rst_n(rst_n),
        .cfg_src_wr(dma_cfg_src_wr), .cfg_dst_wr(dma_cfg_dst_wr),
        .cfg_len_wr(dma_cfg_len_wr), .cfg_data(dma_cfg_data),
        .go(dma_go),
        .busy(dma_busy), .done(dma_done),
        .dma_req(dma_req), .dma_we(dma_we),
        .dma_addr(dma_addr), .dma_wdata(dma_wdata),
        .dma_rdata(dma_rdata), .dma_ready(dma_ready),
        .dma_stall(dma_stall)
    );

    // ---- DMEM ------------------------------------------------------------
    wire        dmem_a_en, dmem_a_we;
    wire [16:0] dmem_a_addr;
    wire [31:0] dmem_a_wdata;
    wire [3:0]  dmem_a_be;
    wire [31:0] dmem_a_rdata;

    wire        dmem_b_en, dmem_b_we;
    wire [16:0] dmem_b_addr;
    wire [31:0] dmem_b_wdata;
    wire [31:0] dmem_b_rdata;

    dmem u_dmem (
        .clk(clk),
        .a_en(dmem_a_en), .a_we(dmem_a_we),
        .a_addr(dmem_a_addr), .a_wdata(dmem_a_wdata),
        .a_be(dmem_a_be), .a_rdata(dmem_a_rdata),
        .b_en(dmem_b_en), .b_we(dmem_b_we),
        .b_addr(dmem_b_addr), .b_wdata(dmem_b_wdata),
        .b_rdata(dmem_b_rdata)
    );

    // ---- UART TX (integrated in soc_top per spec) -----------------------
    wire        uart_wr;
    wire [7:0]  uart_data;
    wire        uart_busy;

    uart_tx #(.CLKS_PER_BIT(434)) u_uart (
        .clk(clk), .rst_n(rst_n),
        .wr(uart_wr), .data(uart_data),
        .busy(uart_busy), .tx(RsTx)
    );

    // ---- CSR counters ----------------------------------------------------
    wire [3:0]  csr_sel;
    wire [31:0] csr_rdata;

    // NN-inference active flag: software sets by writing MMIO
    // 0x1000_1024 (CSR_BASE + 0x24). We capture a write-through bit here.
    // For simplicity, the flag is derived from CSR writes at that offset.
    reg nn_active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) nn_active <= 1'b0;
        else if (cpu_req && cpu_we && (cpu_addr == 32'h1000_1024))
            nn_active <= cpu_wdata[0];
    end

    csr_counters u_csr (
        .clk(clk), .rst_n(rst_n),
        .run(1'b1),
        .mul_busy(mul_busy), .div_busy(div_busy),
        .mac_busy(mac_busy), .cordic_busy(cordic_busy),
        .frontend_stall(frontend_stall), .full_stall(full_stall),
        .dma_busy(dma_busy), .nn_infer_active(nn_active),
        .sel(csr_sel), .rdata(csr_rdata)
    );

    // ---- System bus ------------------------------------------------------
    system_bus u_bus (
        .clk(clk), .rst_n(rst_n),
        .cpu_req(cpu_req), .cpu_we(cpu_we),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_be(cpu_be),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .cpu_stall(),    // CPU always wins in current policy
        .dma_req(dma_req), .dma_we(dma_we),
        .dma_addr(dma_addr), .dma_wdata(dma_wdata),
        .dma_rdata(dma_rdata), .dma_ready(dma_ready),
        .dma_stall(dma_stall),
        .dmem_a_en(dmem_a_en), .dmem_a_we(dmem_a_we),
        .dmem_a_addr(dmem_a_addr), .dmem_a_wdata(dmem_a_wdata),
        .dmem_a_be(dmem_a_be), .dmem_a_rdata(dmem_a_rdata),
        .dmem_b_en(dmem_b_en), .dmem_b_we(dmem_b_we),
        .dmem_b_addr(dmem_b_addr), .dmem_b_wdata(dmem_b_wdata),
        .dmem_b_rdata(dmem_b_rdata),
        .uart_wr(uart_wr), .uart_data(uart_data), .uart_busy(uart_busy),
        .csr_sel(csr_sel), .csr_rdata(csr_rdata)
    );

    // ---- LED status ------------------------------------------------------
    // led[0] = nn_active, led[1] = dma_busy, led[2] = mac_busy,
    // led[3] = cordic_busy, led[4] = mul_busy, led[5] = div_busy,
    // led[15] = heartbeat
    reg [25:0] hb;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) hb <= 0;
        else hb <= hb + 1;
    end
    assign led = {hb[25], 9'b0, div_busy, mul_busy, cordic_busy,
                  mac_busy, dma_busy, nn_active};

endmodule
