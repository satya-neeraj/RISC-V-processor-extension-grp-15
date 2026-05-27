# RISC-V-processor-extension-grp15

#Hardware Acceleration of Neural Network Inference using an Optimized RV32IM Multi-Core Coprocessor on Nexys A7
## Overview
This project presents the design and implementation of an RV32IM RISC-V Processor
with Matrix Multiplication and CORDIC-Based Inverse Trigonometry Accelerators using Verilog HDL.

The processor integrates arithmetic and computation modules including ALU, MUL, DIV, MAC, CORDIC, DMA controller, UART communication, instruction memory, and data memory. 
The design supports FPGA implementation and simulation using Xilinx Vivado and Nexys A7 FPGA board.

The CORDIC accelerator is used for inverse trigonometric computations, while dedicated multiplication hardware is used for matrix multiplication related operations. 
UART communication is used to display execution results stored in registers after instruction execution from memory HEX files.

IMPORTANT NOTE
Do NOT open the .xpr project file by double-clicking it from File Explorer.
This may cause project files to not load properly.

STEPS TO OPEN THE PROJECT
1. Open Xilinx Vivado.
2. Click: File → Project → Open.
3. Navigate to the extracted ZIP folder.
4. Select and open the .xpr file.

SETTING UP THE PROJECT
Ensure the following files are set as Top Modules:
- top_all_module.v
- tb_combined.v

RUNNING THE DESIGN
1. Run Synthesis.type "run all"  in console to check simulation result.
2. Generate the Bitstream.
3. Program the FPGA device.

VIEWING OUTPUT (SERIAL COMMUNICATION)
To observe the output:

1. Install PuTTY.
2. Find the correct COM port:
   - Open Device Manager in Windows.
   - Expand "Ports (COM & LPT)".
   - Look for:
       USB Serial Device (COMx) or
       UART/USB Bridge (COMx)
   - Note the COM number (e.g., COM3, COM5).

3. Open PuTTY and configure:
   - Connection Type: Serial
   - Serial Line: COMx (your detected port)
   - Speed (Baud Rate): 115200

4. Click "Open".

OUTPUT BEHAVIOR
- After programming the FPGA, results will appear in PuTTY.
- Expected delay before output: approximately 27 seconds.

OUTPUT DESCRIPTION
- The displayed results are values stored in registers after execution of instructions from imem.hex.
- The instructions include:
  ADD  - Addition
  SUB  - Subtraction
  MUL  - Multiplication
  DIV  - Division
  MAC  - Multiply-Accumulate
  CORDIC - Iterative algorithm for trigonometric computations

project structure:
```text
Project Root
│
├── Design Sources
│   │
│   ├── Verilog Header
│   │   └── opcode.vh
│   │
│   ├── top_combined (top_all_module.v)
│   │   ├── alu.v
│   │   ├── mul_unit.v
│   │   ├── div_unit.v
│   │   ├── mac_unit.v
│   │   ├── cordic_unit.v
│   │   └── uart_tx.v
│   │
│   ├── soc_top (soc_top.v)
│   │   ├── clk_rst.v
│   │   ├── imem.v
│   │   ├── cpu_top.v
│   │   ├── mac_unit.v
│   │   ├── cordic_unit.v
│   │   ├── dma_controller.v
│   │   ├── dmem.v
│   │   ├── uart_tx.v
│   │   ├── csr_counters.v
│   │   └── system_bus.v
│   │
│   ├── top_cordic (top_cordic_fpga.v)
│   │   ├── alu.v
│   │   ├── mul_unit.v
│   │   ├── div_unit.v
│   │   ├── mac_unit.v
│   │   ├── cordic_unit.v
│   │   └── uart_tx.v
│   │
│   ├── top_div (top_div_fpga.v)
│   │   ├── alu.v
│   │   ├── mul_unit.v
│   │   ├── div_unit.v
│   │   ├── mac_unit.v
│   │   ├── cordic_unit.v
│   │   └── uart_tx.v
│   │
│   ├── top_mac (system_top.v)
│   │   ├── alu.v
│   │   ├── mul_unit.v
│   │   ├── div_unit.v
│   │   ├── mac_unit.v
│   │   ├── cordic_unit.v
│   │   └── uart_tx.v
│   │
│   ├── top_mul (top_mul_fpga.v)
│   │   ├── alu.v
│   │   ├── mul_unit.v
│   │   ├── div_unit.v
│   │   ├── mac_unit.v
│   │   ├── cordic_unit.v
│   │   └── uart_tx.v
│   │
│   └── top_dma_fpga (top_controller.v)
│       └── dma_controller.v
│
├── Memory Files
│   ├── dmem.hex
│   ├── imem.hex
│   ├── imem_combined.hex
│   ├── imem_cordic.hex
│   ├── imem_div.hex
│   ├── imem_mac.hex
│   └── imem_mul.hex
│
├── Constraints
│   └── nexys_a7.xdc
│
├── Simulation Sources
│   │
│   ├── Verilog Header
│   │   └── opcode.vh
│   │
│   ├── tb_combined (tb_all.v)
│   │   └── DUT : top_combined
│   │
│   ├── tb_cpu (tb_cpu.v)
│   │   ├── imem.v
│   │   └── cpu_top.v
│   │
│   ├── tb_alu (tb_alu.v)
│   │   └── DUT : alu.v
│   │
│   ├── tb_cordic (tb_cordic.v)
│   │   └── DUT : top_cordic_fpga.v
│   │
│   ├── tb_div (tb_div.v)
│   │   └── DUT : top_div_fpga.v
│   │
│   ├── tb_dma (tb_dma.v)
│   │   └── DUT : dma_controller.v
│   │
│   ├── tb_mac (tb_mac.v)
│   │   └── DUT : system_top.v
│   │
│   ├── tb_mul (tb_mul.v)
│   │   └── DUT : top_mul_fpga.v
│   │
│   ├── tb_soc_top (tb_soc_top.v)
│   │   └── DUT : soc_top.v
│   │
│   └── tb_uart (tb_uart.v)
│       └── DUT : uart_tx.v
│
└── Utility Sources
```

## Memory Files
- imem.hex              → Main instruction memory
- dmem.hex              → Data memory
- imem_mul.hex          → MUL operation program
- imem_div.hex          → DIV operation program
- imem_mac.hex          → MAC operation program
- imem_cordic.hex       → CORDIC operation program
- imem_combined.hex     → Combined execution program

## Target FPGA
- Board: Nexys A7 FPGA
- Toolchain: Xilinx Vivado

## Features
- RISC-V based pipelined CPU
- ALU operations
- Multiplication and division units
- MAC (Multiply-Accumulate) unit
- CORDIC accelerator
- DMA controller
- UART communication
- FPGA support using Nexys A7
- Vivado simulation support
- Memory initialization using HEX files
