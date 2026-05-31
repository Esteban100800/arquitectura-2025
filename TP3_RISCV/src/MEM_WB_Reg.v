// ============================================================
// MEM_WB_Reg.v  -  Registro de pipeline entre MEM y WB
// Pipeline RISC-V de 5 etapas: IF | ID | EX | MEM | WB
// ============================================================
module MEM_WB_Reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        freeze,         // Congela el registro (debug halt)

    // Entradas desde MEM
    input  wire [31:0] in_pc_plus4,
    input  wire [31:0] in_alu_result,
    input  wire [31:0] in_mem_data,
    input  wire [4:0]  in_rd_addr,
    input  wire        in_reg_write,
    input  wire        in_mem_to_reg,

    // Salidas hacia WB
    output reg  [31:0] out_pc_plus4,
    output reg  [31:0] out_alu_result,
    output reg  [31:0] out_mem_data,
    output reg  [4:0]  out_rd_addr,
    output reg         out_reg_write,
    output reg         out_mem_to_reg
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            out_pc_plus4   <= 32'h0;
            out_alu_result <= 32'h0;
            out_mem_data   <= 32'h0;
            out_rd_addr    <= 5'h0;
            out_reg_write  <= 1'b0;
            out_mem_to_reg <= 1'b0;
        end
        else if (!freeze) begin
            out_pc_plus4   <= in_pc_plus4;
            out_alu_result <= in_alu_result;
            out_mem_data   <= in_mem_data;
            out_rd_addr    <= in_rd_addr;
            out_reg_write  <= in_reg_write;
            out_mem_to_reg <= in_mem_to_reg;
        end
    end

endmodule
