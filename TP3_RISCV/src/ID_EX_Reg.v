// ============================================================
// ID_EX_Reg.v  -  Registro de pipeline entre ID y EX
// Pipeline RISC-V de 5 etapas: IF | ID | EX | MEM | WB
// ============================================================
module ID_EX_Reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,          // Inserta burbuja (branch o load-use)
    input  wire        freeze,         // Congela el registro (debug halt)

    // Entradas desde ID
    input  wire [31:0] in_pc,
    input  wire [31:0] in_pc_plus4,
    input  wire [31:0] in_rs1_data,
    input  wire [31:0] in_rs2_data,
    input  wire [31:0] in_imm,
    input  wire [4:0]  in_rs1_addr,
    input  wire [4:0]  in_rs2_addr,
    input  wire [4:0]  in_rd_addr,
    input  wire [3:0]  in_alu_op,
    input  wire        in_alu_src,
    input  wire        in_mem_read,
    input  wire        in_mem_write,
    input  wire        in_reg_write,
    input  wire        in_mem_to_reg,
    input  wire        in_branch,
    input  wire        in_jump,

    // Salidas hacia EX
    output reg  [31:0] out_pc,
    output reg  [31:0] out_pc_plus4,
    output reg  [31:0] out_rs1_data,
    output reg  [31:0] out_rs2_data,
    output reg  [31:0] out_imm,
    output reg  [4:0]  out_rs1_addr,
    output reg  [4:0]  out_rs2_addr,
    output reg  [4:0]  out_rd_addr,
    output reg  [3:0]  out_alu_op,
    output reg         out_alu_src,
    output reg         out_mem_read,
    output reg         out_mem_write,
    output reg         out_reg_write,
    output reg         out_mem_to_reg,
    output reg         out_branch,
    output reg         out_jump
);

    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            // Burbuja NOP: todas las señales de control a 0
            // Los datos pueden quedar en 0 sin efecto secundario
            out_pc        <= 32'h0;
            out_pc_plus4  <= 32'h4;
            out_rs1_data  <= 32'h0;
            out_rs2_data  <= 32'h0;
            out_imm       <= 32'h0;
            out_rs1_addr  <= 5'h0;
            out_rs2_addr  <= 5'h0;
            out_rd_addr   <= 5'h0;
            out_alu_op    <= 4'h0;
            out_alu_src   <= 1'b0;
            out_mem_read  <= 1'b0;
            out_mem_write <= 1'b0;
            out_reg_write <= 1'b0;
            out_mem_to_reg<= 1'b0;
            out_branch    <= 1'b0;
            out_jump      <= 1'b0;
        end
        else if (!freeze) begin
            out_pc        <= in_pc;
            out_pc_plus4  <= in_pc_plus4;
            out_rs1_data  <= in_rs1_data;
            out_rs2_data  <= in_rs2_data;
            out_imm       <= in_imm;
            out_rs1_addr  <= in_rs1_addr;
            out_rs2_addr  <= in_rs2_addr;
            out_rd_addr   <= in_rd_addr;
            out_alu_op    <= in_alu_op;
            out_alu_src   <= in_alu_src;
            out_mem_read  <= in_mem_read;
            out_mem_write <= in_mem_write;
            out_reg_write <= in_reg_write;
            out_mem_to_reg<= in_mem_to_reg;
            out_branch    <= in_branch;
            out_jump      <= in_jump;
        end
    end

endmodule
