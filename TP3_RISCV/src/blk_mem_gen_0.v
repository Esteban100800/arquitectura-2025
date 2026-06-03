// ============================================================
// blk_mem_gen_0.v - Stub para simulacion del IP de Xilinx
// (Block Memory Generator, Simple Dual Port BRAM 256x32)
//
// Modela:
//   - Port A: escritura sincronica (wea actua como write enable)
//   - Port B: lectura sincronica con 1 ciclo de latencia (doutb registrado)
// ============================================================
module blk_mem_gen_0 (
    // Port A - escritura
    input  wire        clka,
    input  wire        ena,
    input  wire [3:0]  wea,
    input  wire [7:0]  addra,
    input  wire [31:0] dina,
    // Port B - lectura
    input  wire        clkb,
    input  wire        enb,
    input  wire [7:0]  addrb,
    output reg  [31:0] doutb
);
    reg [31:0] mem [0:255];

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) mem[i] = 32'h0;
        doutb = 32'h0;
    end

    // Port A: escritura sincronica
    // Cualquier bit de wea activo => escribe la palabra completa
    // (el RTL real usa wea = {4{debug_we}}, todo 0 o todo 1)
    always @(posedge clka) begin
        if (ena && |wea)
            mem[addra] <= dina;
    end

    // Port B: lectura sincronica de 1 ciclo
    always @(posedge clkb) begin
        if (enb)
            doutb <= mem[addrb];
    end
endmodule