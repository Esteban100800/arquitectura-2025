// ============================================================
// IF_Stage.v  -  Instruction Fetch
// Pipeline RISC-V de 5 etapas: IF | ID | EX | MEM | WB
//
// Usa blk_mem_gen_0 (Simple Dual Port BRAM, 256x32):
//   Port A → debug unit (escritura desde PC via UART)
//   Port B → CPU fetch  (lectura, 1 ciclo de latencia)
//
// Como la BRAM tarda 1 ciclo en responder, se le pasa el
// PRÓXIMO PC (next_pc, combinacional) como dirección. Así
// el dato llega justo cuando el PC ya registró ese valor.
// ============================================================
module IF_Stage (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        branch_taken,
    input  wire [31:0] branch_target,

    output reg  [31:0] pc,
    output wire [31:0] instruction,
    output wire [31:0] pc_plus4,

    // Puerto de escritura desde la debug unit (Port A de la BRAM)
    input  wire        debug_we,
    input  wire [31:0] debug_addr,
    input  wire [31:0] debug_wdata
);

    assign pc_plus4 = pc + 32'd4;

    // ----------------------------------------------------------
    // Calcular el siguiente PC (combinacional)
    // Es la dirección que se le pasa a la BRAM para que el dato
    // esté listo cuando el PC registre ese mismo valor
    // ----------------------------------------------------------
    wire [31:0] next_pc = branch_taken ? branch_target :
                          stall        ? pc            :
                                         pc_plus4;

    // ----------------------------------------------------------
    // Registro del PC
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            pc <= 32'h0000_0000;
        else if (branch_taken || !stall)
            pc <= next_pc;
    end

    // ----------------------------------------------------------
    // BRAM: Simple Dual Port, 256 palabras x 32 bits
    //   Port A: debug unit escribe instrucciones (wea = 4 bits,
    //           uno por byte, todos en 1 para escritura completa)
    //   Port B: CPU lee instrucciones (solo lectura, enb siempre 1)
    // ----------------------------------------------------------
    blk_mem_gen_0 imem (
        // Port A — escritura desde debug unit
        .clka  (clk),
        .ena   (1'b1),
        .wea   ({4{debug_we}}),          // 4'b1111 si debug_we, 4'b0000 si no
        .addra (debug_addr[9:2]),         // índice de palabra (bits [9:2])
        .dina  (debug_wdata),

        // Port B — lectura del CPU (next_pc para compensar latencia)
        .clkb  (clk),
        .enb   (1'b1),
        .addrb (next_pc[9:2]),            // próximo PC → dato listo 1 ciclo después
        .doutb (instruction)
    );

endmodule
