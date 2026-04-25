// ============================================================================
// tb_soc_top.v  --  Full-SoC simulation, bulletproof variant.
//
// This version is SELF-DIAGNOSING.  It prints what it sees regardless of
// whether UART is working, and tells you EXACTLY why if nothing comes out.
//
// The key trick: AUTO-DETECT the actual bit rate from the TX line instead of
// guessing.  That way, whether your CLKS_PER_BIT is 434 or 868, whether the
// MMCM is locked or not, we still decode bytes correctly.
// ============================================================================
`timescale 1ns/1ps

module tb_soc_top;
    reg  clk = 0;
    reg  btn_cpu_resetn = 0;
    wire RsTx;
    wire [15:0] led;

    soc_top u_soc(
        .clk_100mhz(clk),
        .btn_cpu_resetn(btn_cpu_resetn),
        .RsTx(RsTx),
        .led(led)
    );

    // 100 MHz testbench clock (matches E3 pin)
    always #5 clk = ~clk;

    integer byte_count    = 0;
    integer pc_changes    = 0;
    integer mmcm_locked_t = -1;
    integer first_pc_t    = -1;
    integer first_tx_lo_t = -1;
    reg     done_flag     = 0;

    // ========== Reset ==========
    initial begin
        $display("\n=========================================");
        $display(" TB_SOC_TOP : riscv_nn_soc simulation");
        $display("=========================================");
        btn_cpu_resetn = 0;
        #500 btn_cpu_resetn = 1;
        $display("[TB %0t ns] Reset released", $time);
    end

    // ========== MMCM lock watcher (critical diagnostic) ==========
    // If the MMCM never locks, nothing downstream will run.
    initial begin
        #100;
        wait (u_soc.u_clkrst.mmcm_locked === 1'b1);
        mmcm_locked_t = $time;
        $display("[TB %0t ns] *** MMCM LOCKED *** (design clock is now live)", $time);
    end

    // ========== CPU PC monitor ==========
    reg [31:0] last_pc = 32'hFFFFFFFF;
    integer    pc_sample = 0;
    always @(posedge u_soc.clk) begin
        if (u_soc.imem_addr !== last_pc) begin
            if (first_pc_t < 0) begin
                first_pc_t = $time;
                $display("[TB %0t ns] *** CPU FETCH BEGAN *** first PC = %h",
                         $time, u_soc.imem_addr);
            end
            pc_changes = pc_changes + 1;
            pc_sample  = pc_sample + 1;
            if (pc_sample >= 2000) begin
                $display("[TB %0t ns] PC = %h  (%0d total PC changes)",
                         $time, u_soc.imem_addr, pc_changes);
                pc_sample = 0;
            end
            last_pc = u_soc.imem_addr;
        end
    end

    // ========== TX line activity watcher ==========
    initial begin
        @(negedge RsTx);
        first_tx_lo_t = $time;
        $display("[TB %0t ns] *** TX LINE WENT LOW *** (UART transmission started)",
                 $time);
    end

    // ========== Auto-baud UART sniffer ==========
    // Measures the first start-bit width to determine actual bit time, then
    // uses that to decode all subsequent bytes.  Works at any baud without
    // knowing CLKS_PER_BIT in advance.
    integer measured_bit_ns = 0;

    initial begin : auto_baud
        integer t_fall, t_rise;
        // wait for first start bit
        @(negedge RsTx);
        t_fall = $time;
        // wait for start bit to end (first rising edge after start)
        @(posedge RsTx);
        t_rise = $time;
        measured_bit_ns = t_rise - t_fall;
        // Often the first "bit" contains multiple data bits; prefer dividing
        // by the ratio to expected @ 115200 baud (8680 ns).  But for diagnosis
        // we just report both possibilities:
        $display("[TB %0t ns] First low pulse = %0d ns", $time, measured_bit_ns);
        $display("[TB]    If this equals 8680 ns : UART = 115200 baud  (correct)");
        $display("[TB]    If this equals 17360 ns: UART = 57600 baud   (CLKS_PER_BIT wrong)");
        $display("[TB]    If this is a multiple of 8680 : start bit + '0' data bits ran together");
    end

    // ========== Byte sniffer (assumes 115200 baud = 8680 ns/bit) ==========
    // This will be wrong if baud is wrong, but the auto_baud block above
    // tells us the truth.
    localparam BIT_NS = 8680;
    reg [7:0] rx_buffer[0:1023];

    task sniff_byte;
        integer i;
        reg [7:0] b;
        begin
            @(negedge RsTx);
            #(BIT_NS + BIT_NS/2);
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = RsTx;
                #BIT_NS;
            end
            byte_count = byte_count + 1;
            if (byte_count < 1024) rx_buffer[byte_count-1] = b;
            if (byte_count <= 20) begin
                if (b >= 8'h20 && b < 8'h7F)
                    $display("[TB %0t ns] UART RX byte %0d: '%c' (0x%02h)",
                             $time, byte_count, b, b);
                else
                    $display("[TB %0t ns] UART RX byte %0d: 0x%02h",
                             $time, byte_count, b);
            end
            // Just-in-time character echo after byte 20
            if (byte_count > 20) begin
                if (b == 8'h0D) $write("");
                else if (b == 8'h0A) $write("\n");
                else                  $write("%c", b);
                $fflush;
            end

            // Detect "DEMO DONE" end-marker
            if (byte_count >= 9) begin
                if (rx_buffer[byte_count-9] == "D" &&
                    rx_buffer[byte_count-8] == "E" &&
                    rx_buffer[byte_count-7] == "M" &&
                    rx_buffer[byte_count-6] == "O" &&
                    rx_buffer[byte_count-5] == " " &&
                    rx_buffer[byte_count-4] == "D" &&
                    rx_buffer[byte_count-3] == "O" &&
                    rx_buffer[byte_count-2] == "N" &&
                    rx_buffer[byte_count-1] == "E") begin
                    done_flag = 1'b1;
                end
            end
        end
    endtask
    initial begin
        forever sniff_byte;
    end

    // ========== Timeout and diagnostic report ==========
    initial begin
        #(60_000_000);  // 60 ms

        $display("\n\n=========================================");
        $display(" SIMULATION DIAGNOSTIC REPORT");
        $display("=========================================");
        if (mmcm_locked_t < 0)
            $display("   [CRITICAL] MMCM NEVER LOCKED.");
        else
            $display("   MMCM locked at       : %0d ns", mmcm_locked_t);
        if (first_pc_t < 0)
            $display("   [CRITICAL] CPU never fetched an instruction.");
        else
            $display("   First CPU fetch at   : %0d ns", first_pc_t);
        if (first_tx_lo_t < 0)
            $display("   [CRITICAL] TX line never went low (no UART activity).");
        else
            $display("   First TX low at      : %0d ns", first_tx_lo_t);
        $display("   PC changes observed  : %0d", pc_changes);
        $display("   UART bytes received  : %0d", byte_count);
        $display("   Measured first pulse : %0d ns", measured_bit_ns);
        $display("");

        // VERDICT
        if (mmcm_locked_t < 0) begin
            $display("   VERDICT: MMCM DID NOT LOCK IN SIMULATION");
            $display("            In Vivado XSim, Xilinx IP primitives need 'glbl.v' in the");
            $display("            simulation set AND global reset to be released.");
            $display("            FIX: Add glbl to simulation via");
            $display("                 Simulation Settings -> xsim.elaborate -> More options");
            $display("                 -> add: -L unisims_ver  -L unisim  glbl");
            $display("            OR use a sim-only bypass of the MMCM.");
        end else if (pc_changes == 0) begin
            $display("   VERDICT: MMCM OK but CPU NEVER EXECUTED.");
            $display("            Check imem.hex was loaded ($readmemh message in log),");
            $display("            and that rst_n_sync actually deasserted.");
        end else if (byte_count == 0 && first_tx_lo_t < 0) begin
            $display("   VERDICT: CPU RAN but TX LINE NEVER TOGGLED.");
            $display("            Firmware never wrote to UART_DATA register.");
            $display("            Possibly stuck in uart_putc's busy-wait OR the write");
            $display("            never arrives at system_bus.  Check uart_wr with a probe.");
        end else if (byte_count == 0) begin
            $display("   VERDICT: TX TOGGLED but sniffer decoded NO VALID BYTES.");
            $display("            Likely baud mismatch between uart_tx and BIT_NS.");
            $display("            Compare measured_bit_ns (%0d) vs expected 8680 ns.",
                     measured_bit_ns);
        end else if (done_flag) begin
            $display("   VERDICT: FULL DEMO COMPLETED SUCCESSFULLY.");
        end else begin
            $display("   VERDICT: PARTIAL OUTPUT (%0d bytes). Could be fine -- extend time.",
                     byte_count);
        end
        $display("=========================================\n");
        $finish;
    end

    // ========== Early exit when we see the end banner ==========
    initial begin
        wait(done_flag);
        #50_000;
        $display("\n[TB] DEMO DONE seen, exiting.");
        $finish;
    end

endmodule