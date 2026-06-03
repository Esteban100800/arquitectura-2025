// ============================================================
// IF_ID_Reg.v  -  Registro de pipeline entre IF e ID
// Pipeline RISC-V de 5 etapas: IF | ID | EX | MEM | WB
// ============================================================
module IF_ID_Reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,          // Congela el registro (hazard de datos)
    input  wire        flush,          // Inserta NOP (branch tomado)

    // Entradas desde IF
    input  wire [31:0] if_pc,
    input  wire [31:0] if_pc_plus4,
    input  wire [31:0] if_instruction,

    // Salidas hacia ID
    output reg  [31:0] id_pc,
    output reg  [31:0] id_pc_plus4,
    output reg  [31:0] id_instruction
);

    // NOP canónico RISC-V: addi x0, x0, 0  →  0x00000013
    localparam NOP = 32'h0000_0013;

    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            // Flush: limpia el registro e inserta NOP para evitar
            // que una instrucción incorrecta avance al decodificador
            id_pc          <= 32'h0000_0000;
            id_pc_plus4    <= 32'h0000_0004;
            id_instruction <= NOP;
        end
        else if (!stall) begin
            // Avance normal: propaga los valores de IF a ID
            id_pc          <= if_pc;
            id_pc_plus4    <= if_pc_plus4;
            id_instruction <= if_instruction;
        end
        // Si stall==1, los valores se mantienen (burbuja retenida)
    end

endmodule
