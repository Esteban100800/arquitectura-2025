// ============================================================
// Forwarding_Unit.v  -  Unidad de forwarding de datos
// Pipeline RISC-V de 5 etapas: IF | ID | EX | MEM | WB
//
// Evita stalls por dependencias de datos haciendo bypass directo
// desde los registros de pipeline hacia las entradas de la ALU.
//
// Salidas fwd_a / fwd_b:
//   2'b00  →  sin forwarding (usa valor del banco de registros)
//   2'b10  →  forward desde EX/MEM (instrucción 1 ciclo atrás)
//   2'b01  →  forward desde MEM/WB (instrucción 2 ciclos atrás)
//
// Prioridad: EX/MEM tiene precedencia sobre MEM/WB
// (el valor más reciente es el correcto cuando ambos coinciden).
// ============================================================
module Forwarding_Unit (
    input  wire [4:0]  ex_rs1_addr,    // rs1 de la instrucción en EX
    input  wire [4:0]  ex_rs2_addr,    // rs2 de la instrucción en EX
    input  wire [4:0]  mem_rd_addr,    // rd  de la instrucción en MEM
    input  wire        mem_reg_write,  // La instrucción en MEM escribe un registro
    input  wire [4:0]  wb_rd_addr,     // rd  de la instrucción en WB
    input  wire        wb_reg_write,   // La instrucción en WB escribe un registro

    output reg  [1:0]  fwd_a,          // Selector de forwarding para operando A
    output reg  [1:0]  fwd_b           // Selector de forwarding para operando B
);

    always @(*) begin
        // --- Forwarding para el operando A (rs1) ---
        if (mem_reg_write && (mem_rd_addr != 5'b0) && (mem_rd_addr == ex_rs1_addr))
            fwd_a = 2'b10;  // Forward desde EX/MEM (más reciente)
        else if (wb_reg_write && (wb_rd_addr != 5'b0) && (wb_rd_addr == ex_rs1_addr))
            fwd_a = 2'b01;  // Forward desde MEM/WB
        else
            fwd_a = 2'b00;  // Sin forwarding

        // --- Forwarding para el operando B (rs2) ---
        if (mem_reg_write && (mem_rd_addr != 5'b0) && (mem_rd_addr == ex_rs2_addr))
            fwd_b = 2'b10;  // Forward desde EX/MEM (más reciente)
        else if (wb_reg_write && (wb_rd_addr != 5'b0) && (wb_rd_addr == ex_rs2_addr))
            fwd_b = 2'b01;  // Forward desde MEM/WB
        else
            fwd_b = 2'b00;  // Sin forwarding
    end

endmodule
