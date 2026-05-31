// ============================================================
// EX_MEM_Reg.v  -  Registro de pipeline entre EX y MEM
// Pipeline RISC-V de 5 etapas: IF | ID | EX | MEM | WB
// ============================================================
module EX_MEM_Reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        freeze,         // Congela el registro (debug halt)
    input  wire        flush,          // Limpia el registro (branch tomado en MEM)

    // Entradas desde EX
    input  wire [31:0] in_pc_plus4,
    input  wire [31:0] in_alu_result,
    input  wire [31:0] in_rs2_data,
    input  wire [4:0]  in_rd_addr,
    input  wire        in_mem_read,
    input  wire        in_mem_write,
    input  wire        in_reg_write,
    input  wire        in_mem_to_reg,
    input  wire        in_branch_taken,
    input  wire [31:0] in_branch_target,

    // Salidas hacia MEM
    output reg  [31:0] out_pc_plus4,
    output reg  [31:0] out_alu_result,
    output reg  [31:0] out_rs2_data,
    output reg  [4:0]  out_rd_addr,
    output reg         out_mem_read,
    output reg         out_mem_write,
    output reg         out_reg_write,
    output reg         out_mem_to_reg,
    output reg         out_branch_taken,
    output reg  [31:0] out_branch_target
);

    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            out_pc_plus4    <= 32'h0;
            out_alu_result  <= 32'h0;
            out_rs2_data    <= 32'h0;
            out_rd_addr     <= 5'h0;
            out_mem_read    <= 1'b0;
            out_mem_write   <= 1'b0;
            out_reg_write   <= 1'b0;
            out_mem_to_reg  <= 1'b0;
            out_branch_taken  <= 1'b0;
            out_branch_target <= 32'h0;
        end
        else if (!freeze) begin
            out_pc_plus4    <= in_pc_plus4;
            out_alu_result  <= in_alu_result;
            out_rs2_data    <= in_rs2_data;
            out_rd_addr     <= in_rd_addr;
            out_mem_read    <= in_mem_read;
            out_mem_write   <= in_mem_write;
            out_reg_write   <= in_reg_write;
            out_mem_to_reg  <= in_mem_to_reg;
            out_branch_taken  <= in_branch_taken;
            out_branch_target <= in_branch_target;
        end
    end

endmodule
