
module halt_detection_unit (
    input  wire clk,
    input  wire rst,
    input  wire halt_instr,   // HALT detectado en id_instruction (RISCV_Top)
    input  wire resume,       // pulso: sale del halt y reanuda ejecución
    input  wire clk_en,       // solo avanzar FSM cuando el pipeline puede avanzar
    input  wire cancel,       // branch tomado: HALT era especulativo, abortar drain

    output wire flush_if_id,  // pulso 1 ciclo: mete NOP en IF/ID
    output wire freeze_if,    // congela PC  (IF no avanza)
    output wire stall_if_id,  // stalla IF/ID (mantiene el NOP)
    output wire freeze_all,   // congela ID/EX, EX/MEM, MEM/WB
    output wire halt_done     // pipeline vacío y congelado
);

    // Estados de la FSM
    //   IDLE   → pipeline corriendo normalmente
    //   DRAIN1 → ciclo 1: C (en MEM/WB) completa WB
    //   DRAIN2 → ciclo 2: B (en EX/MEM) completa WB
    //   DRAIN3 → ciclo 3: A (en ID/EX)  completa WB
    //   HALTED → pipeline vacío y congelado, espera resume
    localparam IDLE   = 3'd0,
               DRAIN1 = 3'd1,
               DRAIN2 = 3'd2,
               DRAIN3 = 3'd3,
               HALTED = 3'd4;

    reg [2:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst)
            state <= IDLE;
        else if (clk_en) case (state)
            IDLE:   if (halt_instr)  state <= DRAIN1;
            DRAIN1: if (cancel)      state <= IDLE; else state <= DRAIN2;
            DRAIN2: if (cancel)      state <= IDLE; else state <= DRAIN3;
            DRAIN3: if (cancel)      state <= IDLE; else state <= HALTED;
            HALTED: if (resume)      state <= IDLE;
            default:                 state <= IDLE;
        endcase
    end

    // flush_if_id:  pulso en el ciclo de detección (IDLE + halt_instr)
    assign flush_if_id = (state == IDLE)   && halt_instr;

    //  congela PC también en el ciclo de detección para no perder
    // la instrucción que sigue al HALT (estaba entrando a IF).
    // En HALTED no congela IF: cuando el debug_unit hace resume (step/run),
    // el PC ya puede avanzar en ese mismo ciclo sin esperar un ciclo extra.
    assign freeze_if   = (state != IDLE) || halt_instr;
    assign stall_if_id = (state != IDLE);

    // solo en HALTED
    assign freeze_all  = (state == HALTED);
    assign halt_done   = (state == HALTED);

endmodule
