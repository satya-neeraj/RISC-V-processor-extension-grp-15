// ============================================================================
// control_unit.v  --  pure combinational decoder
// Emits class flags (is_mul, is_mac, ...) + ALU op + imm.
// ============================================================================
`timescale 1ns/1ps
`include "opcode.vh"

module control_unit (
    input  wire [31:0] instr,

    // class flags
    output reg         is_alu,
    output reg         is_load,
    output reg         is_store,
    output reg         is_branch,
    output reg         is_jal,
    output reg         is_jalr,
    output reg         is_lui,
    output reg         is_auipc,
    output reg         is_mul,
    output reg         is_div,
    output reg         is_rem,
    output reg         is_mac_clr,
    output reg         is_mac_acc,
    output reg         is_mac_rd,
    output reg         is_cordic,      // any CORDIC op
    output reg  [1:0]  cordic_mode,    // 0=asin,1=acos,2=atan
    output reg         is_dma_src,
    output reg         is_dma_dst,
    output reg         is_dma_len,
    output reg         is_dma_go,

    // decoded fields
    output wire [4:0]  rs1_addr,
    output wire [4:0]  rs2_addr,
    output wire [4:0]  rd_addr,
    output reg  [31:0] imm,
    output reg  [3:0]  alu_op,
    output reg         reg_we,         // will writeback?
    output reg         use_imm,        // EX should use imm instead of rs2
    // which stage writes the register
    output reg         wb_from_ex,     // ALU/LUI/AUIPC/JAL/JALR/MUL/DIV/REM
    output reg         wb_from_mwb     // LOAD / MAC.RD / CORDIC
);

    wire [6:0] opcode = instr[6:0];
    wire [2:0] f3     = instr[14:12];
    wire [6:0] f7     = instr[31:25];

    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];
    assign rd_addr  = instr[11:7];

    // Sign-extended immediates
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7],
                         instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12],
                         instr[20], instr[30:21], 1'b0};

    always @(*) begin
        // defaults
        is_alu      = 1'b0;
        is_load     = 1'b0;
        is_store    = 1'b0;
        is_branch   = 1'b0;
        is_jal      = 1'b0;
        is_jalr     = 1'b0;
        is_lui      = 1'b0;
        is_auipc    = 1'b0;
        is_mul      = 1'b0;
        is_div      = 1'b0;
        is_rem      = 1'b0;
        is_mac_clr  = 1'b0;
        is_mac_acc  = 1'b0;
        is_mac_rd   = 1'b0;
        is_cordic   = 1'b0;
        cordic_mode = 2'b00;
        is_dma_src  = 1'b0;
        is_dma_dst  = 1'b0;
        is_dma_len  = 1'b0;
        is_dma_go   = 1'b0;
        imm         = 32'b0;
        alu_op      = `ALU_ADD;
        reg_we      = 1'b0;
        use_imm     = 1'b0;
        wb_from_ex  = 1'b0;
        wb_from_mwb = 1'b0;

        case (opcode)
            `OP_LUI: begin
                is_lui     = 1'b1;
                imm        = imm_u;
                alu_op     = `ALU_LUI;
                reg_we     = 1'b1;
                use_imm    = 1'b1;
                wb_from_ex = 1'b1;
            end
            `OP_AUIPC: begin
                is_auipc   = 1'b1;
                imm        = imm_u;
                alu_op     = `ALU_ADD;
                reg_we     = 1'b1;
                use_imm    = 1'b1;
                wb_from_ex = 1'b1;
            end
            `OP_JAL: begin
                is_jal     = 1'b1;
                imm        = imm_j;
                reg_we     = 1'b1;
                wb_from_ex = 1'b1;
            end
            `OP_JALR: begin
                is_jalr    = 1'b1;
                imm        = imm_i;
                reg_we     = 1'b1;
                use_imm    = 1'b1;
                wb_from_ex = 1'b1;
            end
            `OP_BRANCH: begin
                is_branch = 1'b1;
                imm       = imm_b;
            end
            `OP_LOAD: begin
                is_load     = 1'b1;
                imm         = imm_i;
                alu_op      = `ALU_ADD;
                reg_we      = 1'b1;
                use_imm     = 1'b1;
                wb_from_mwb = 1'b1;
            end
            `OP_STORE: begin
                is_store = 1'b1;
                imm      = imm_s;
                alu_op   = `ALU_ADD;
                use_imm  = 1'b1;
            end
            `OP_ALUI: begin
                is_alu     = 1'b1;
                imm        = imm_i;
                use_imm    = 1'b1;
                reg_we     = 1'b1;
                wb_from_ex = 1'b1;
                case (f3)
                    3'b000: alu_op = `ALU_ADD;   // ADDI
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                    3'b001: alu_op = `ALU_SLL;
                    3'b101: alu_op = (instr[30]) ? `ALU_SRA : `ALU_SRL;
                    default: alu_op = `ALU_ADD;
                endcase
            end
            `OP_ALUR: begin
                is_alu     = 1'b1;
                reg_we     = 1'b1;
                wb_from_ex = 1'b1;
                case (f3)
                    3'b000: alu_op = (instr[30]) ? `ALU_SUB : `ALU_ADD;
                    3'b001: alu_op = `ALU_SLL;
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b101: alu_op = (instr[30]) ? `ALU_SRA : `ALU_SRL;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                    default: alu_op = `ALU_ADD;
                endcase
            end
            `OP_MULDIV: begin
                reg_we     = 1'b1;
                wb_from_ex = 1'b1;   // MUL/DIV writeback comes out of EX (after done)
                case (f3)
                    `F3_MUL: is_mul = 1'b1;
                    `F3_DIV: is_div = 1'b1;
                    `F3_REM: is_rem = 1'b1;
                    default: ;
                endcase
            end
            `OP_MAC: begin
                case (f3)
                    `F3_MAC_CLR: is_mac_clr = 1'b1;
                    `F3_MAC_ACC: is_mac_acc = 1'b1;
                    `F3_MAC_RD:  begin
                        is_mac_rd   = 1'b1;
                        reg_we      = 1'b1;
                        wb_from_mwb = 1'b1;
                    end
                    default: ;
                endcase
            end
            `OP_CORDIC: begin
                is_cordic   = 1'b1;
                cordic_mode = f3[1:0];   // 00 asin, 01 acos, 10 atan
                reg_we      = 1'b1;
                wb_from_mwb = 1'b1;
            end
            `OP_DMA: begin
                case (f3)
                    `F3_DMA_SRC: is_dma_src = 1'b1;
                    `F3_DMA_DST: is_dma_dst = 1'b1;
                    `F3_DMA_LEN: is_dma_len = 1'b1;
                    `F3_DMA_GO:  is_dma_go  = 1'b1;
                    default: ;
                endcase
            end
            `OP_FENCE, `OP_SYSTEM: begin
                // treat as NOP -- CSR reads are done via LW to CSR_BASE MMIO
            end
            default: ;
        endcase
    end

endmodule
