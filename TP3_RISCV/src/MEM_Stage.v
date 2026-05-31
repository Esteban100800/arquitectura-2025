// ============================================================
// MEM_Stage.v  -  Memory Access (datos)
// Pipeline RISC-V de 5 etapas: IF | ID | EX | MEM | WB
//
// Memoria de datos: 256 palabras de 32 bits (1 KB)
// Solo acceso de palabra completa (LW/SW).
// La dirección se indexa con address[9:2] (word-aligned).
// ============================================================
module MEM_Stage (
    input  wire        clk,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [31:0] address,
    input  wire [31:0] write_data,
    output wire [31:0] read_data,
    // Puerto de acceso para debug unit
    input  wire [31:0] debug_addr,
    input  wire [31:0] debug_wdata,
    input  wire        debug_we,
    output wire [31:0] debug_rdata
);

    reg [31:0] dmem [0:255];

    // Escritura síncrona (CPU o debug unit)
    always @(posedge clk) begin
        if (mem_write)
            dmem[address[9:2]] <= write_data;
        else if (debug_we)
            dmem[debug_addr[9:2]] <= debug_wdata;
    end

    // Lectura combinacional
    assign read_data   = mem_read ? dmem[address[9:2]]    : 32'h0;
    assign debug_rdata = dmem[debug_addr[9:2]];

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            dmem[i] = 32'h0000_0000;
    end

endmodule
