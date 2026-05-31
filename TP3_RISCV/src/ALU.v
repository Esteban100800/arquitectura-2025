// ============================================================
// ALU.v  -  Unidad Aritmético-Lógica RISC-V (RV32I)
// Usada por: EX_Stage
//
// Codificación de alu_op[3:0]:
//   0000  ADD    a + b
//   0001  SUB    a - b
//   0010  SLL    a << b[4:0]
//   0011  SLT    a < b (con signo)   → 1 ó 0
//   0100  SLTU   a < b (sin signo)   → 1 ó 0
//   0101  XOR    a ^ b
//   0110  SRL    a >> b[4:0]  (lógico)
//   0111  SRA    a >> b[4:0]  (aritmético)
//   1000  OR     a | b
//   1001  AND    a & b
//   1010  PASSB  b            (para LUI: resultado = inmediato)
//   otros ADD por defecto
//
// Flags de salida:
//   zero  → resultado == 0
// ============================================================
module ALU (
    input  wire [31:0] op_a,
    input  wire [31:0] op_b,
    input  wire [3:0]  alu_op,
    output reg  [31:0] result,
    output wire        zero
);

    always @(*) begin
        case (alu_op)
            4'b0000: result = op_a + op_b;
            4'b0001: result = op_a - op_b;
            4'b0010: result = op_a << op_b[4:0];
            4'b0011: result = ($signed(op_a) < $signed(op_b)) ? 32'd1 : 32'd0;
            4'b0100: result = (op_a < op_b)                   ? 32'd1 : 32'd0;
            4'b0101: result = op_a ^ op_b;
            4'b0110: result = op_a >> op_b[4:0];
            4'b0111: result = $signed(op_a) >>> op_b[4:0];
            4'b1000: result = op_a | op_b;
            4'b1001: result = op_a & op_b;
            4'b1010: result = op_b;                            // PASSB (LUI)
            default: result = op_a + op_b;
        endcase
    end

    assign zero = (result == 32'b0);

endmodule
