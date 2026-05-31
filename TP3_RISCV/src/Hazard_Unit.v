// ============================================================
// Hazard_Unit.v  -  Detección de hazards y generación de stalls
// Pipeline RISC-V de 5 etapas: IF | ID | EX | MEM | WB
//
// Hazards detectados:
// 1. Load-Use: la instrucción en EX hace un Load y la siguiente
//    instrucción (en ID) lee el registro destino del Load.
//    → stall=1 (congela PC y IF/ID), id_ex_flush=1 (burbuja en EX)
//
// 2. Branch/Jump tomado: branch_taken viene desde EX/MEM (registrado).
//    Las instrucciones en IF, ID y EX son incorrectas (3 ciclos de penalidad).
//    → if_id_flush=1, id_ex_flush=1, ex_mem_flush=1
// ============================================================
module Hazard_Unit (
    input  wire [4:0]  id_rs1_addr,    // rs1 de la instrucción en ID
    input  wire [4:0]  id_rs2_addr,    // rs2 de la instrucción en ID
    input  wire [4:0]  ex_rd_addr,     // rd  de la instrucción en EX
    input  wire        ex_mem_read,    // La instrucción en EX es un Load
    input  wire        branch_taken,   // Salto tomado (viene de EX/MEM, registrado)

    output wire        stall,          // Congela PC y registro IF/ID
    output wire        if_id_flush,    // Limpia el registro IF/ID
    output wire        id_ex_flush,    // Limpia el registro ID/EX
    output wire        ex_mem_flush    // Limpia el registro EX/MEM
);

    wire load_use_hazard = ex_mem_read
                         && (ex_rd_addr != 5'b0)
                         && ((ex_rd_addr == id_rs1_addr) || (ex_rd_addr == id_rs2_addr));

    assign stall        = load_use_hazard;
    assign if_id_flush  = branch_taken;
    assign id_ex_flush  = load_use_hazard || branch_taken;
    assign ex_mem_flush = branch_taken;

endmodule
