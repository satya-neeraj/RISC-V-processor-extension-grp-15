// ============================================================================
// opcode.vh   --  ISA encoding for RV32I + custom extensions
// (Verilog-2001; include guarded)
// ============================================================================
`ifndef OPCODE_VH
`define OPCODE_VH

// ---------- RV32I base opcodes (opcode[6:0]) -------------------------------
`define OP_LUI     7'b0110111   // 0x37
`define OP_AUIPC   7'b0010111   // 0x17
`define OP_JAL     7'b1101111   // 0x6F
`define OP_JALR    7'b1100111   // 0x67
`define OP_BRANCH  7'b1100011   // 0x63
`define OP_LOAD    7'b0000011   // 0x03
`define OP_STORE   7'b0100011   // 0x23
`define OP_ALUI    7'b0010011   // 0x13   (addi/slti/...)
`define OP_ALUR    7'b0110011   // 0x33   (add/sub/...)
`define OP_FENCE   7'b0001111   // 0x0F   (treated as NOP)
`define OP_SYSTEM  7'b1110011   // 0x73   (CSR + ECALL; CSR handled in HW)

// ---------- Custom opcodes -------------------------------------------------
`define OP_MULDIV  7'b0001011   // 0x0B   custom-0   (MUL/DIV/REM)
`define OP_MAC     7'b0101011   // 0x2B   custom-1
`define OP_CORDIC  7'b1011011   // 0x5B   custom-2
`define OP_DMA     7'b1111011   // 0x7B   custom-3

// ---------- funct3 within custom opcodes -----------------------------------
`define F3_MUL     3'b000
`define F3_DIV     3'b001
`define F3_REM     3'b010

`define F3_MAC_CLR 3'b000
`define F3_MAC_ACC 3'b001
`define F3_MAC_RD  3'b010

`define F3_ASIN    3'b000
`define F3_ACOS    3'b001
`define F3_ATAN    3'b010

`define F3_DMA_SRC 3'b000
`define F3_DMA_DST 3'b001
`define F3_DMA_LEN 3'b010
`define F3_DMA_GO  3'b011

// ---------- funct3 for branches / loads / stores ---------------------------
`define F3_BEQ     3'b000
`define F3_BNE     3'b001
`define F3_BLT     3'b100
`define F3_BGE     3'b101
`define F3_BLTU    3'b110
`define F3_BGEU    3'b111

`define F3_LB      3'b000
`define F3_LH      3'b001
`define F3_LW      3'b010
`define F3_LBU     3'b100
`define F3_LHU     3'b101

`define F3_SB      3'b000
`define F3_SH      3'b001
`define F3_SW      3'b010

// ---------- ALU op selectors (internal, not ISA) ---------------------------
`define ALU_ADD    4'd0
`define ALU_SUB    4'd1
`define ALU_AND    4'd2
`define ALU_OR     4'd3
`define ALU_XOR    4'd4
`define ALU_SLL    4'd5
`define ALU_SRL    4'd6
`define ALU_SRA    4'd7
`define ALU_SLT    4'd8
`define ALU_SLTU   4'd9
`define ALU_LUI    4'd10

// ---------- Memory map -----------------------------------------------------
`define IMEM_BASE   32'h0000_0000
`define IMEM_SIZE   32'h0001_0000   // 64 KB
`define DMEM_BASE   32'h0001_0000
`define DMEM_SIZE   32'h0002_0000   // 128 KB
`define DMEM_END    32'h0003_0000

`define UART_DATA   32'h1000_0000
`define UART_STAT   32'h1000_0004
`define CSR_BASE    32'h1000_1000   // 9 counters, each 4 B

// ---------- Pipeline bubble encoding ---------------------------------------
// A bubble is a canonical NOP: addi x0,x0,0  =>  0x00000013
`define NOP_INSTR   32'h0000_0013

`endif
