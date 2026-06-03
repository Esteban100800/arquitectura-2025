// ============================================================
// WB_Stage.v  -  Write Back
// Pipeline RISC-V de 5 etapas: IF | ID | EX | MEM | WB
//
// Selecciona el dato a escribir en el banco de registros:
//   mem_to_reg=1  →  dato leído de memoria (LW)
//   mem_to_reg=0  →  resultado de la ALU
//                    (para JAL/JALR ya viene PC+4 desde EX)
//
// pc_plus4 se recibe pero no se usa en la mux final, ya que
// EX_Stage sobreescribe alu_result con PC+4 para saltos.
// Se mantiene el puerto para compatibilidad y depuración.
// ============================================================
module WB_Stage (
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_data,
    input  wire [31:0] pc_plus4,
    input  wire        mem_to_reg,
    output wire [31:0] write_data
);

    assign write_data = mem_to_reg ? mem_data : alu_result;

endmodule
