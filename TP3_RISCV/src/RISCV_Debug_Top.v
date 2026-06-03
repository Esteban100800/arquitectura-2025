// ============================================================
// RISCV_Debug_Top.v  -  Top level con Debug Unit + UART
//
// Conecta:
//   RISCV_Top   → procesador pipeline de 5 etapas
//   debug_unit  → interpreta comandos del protocolo serial
//   UART        → transceptor serie a 9600 baud
//
// Pines hacia la FPGA:
//   clk, rst   → reloj y reset de la placa
//   rx         → pin RX del puerto USB-UART
//   tx         → pin TX del puerto USB-UART
// ============================================================
module RISCV_Debug_Top (
    input  wire clk,       // 100 MHz desde la placa
    input  wire rst,
    input  wire rx,
    output wire tx
);

    // --------------------------------------------------------
    // Clock Wizard: 100 MHz → 50 MHz
    // --------------------------------------------------------
    wire clk_50;
    wire locked;

    clk_wiz_0 u_clk_wiz (
        .clk_in1  (clk),
        .clk_out1 (clk_50),
        .reset    (rst),
        .locked   (locked)
    );

    // Reset sincronizado: esperar a que el PLL esté bloqueado
    wire rst_sync = rst || !locked;

    // --------------------------------------------------------
    // Wires UART ↔ debug_unit
    // --------------------------------------------------------
    wire [7:0] uart_rx_data;
    wire       uart_rx_valid;   // pulso: byte recibido
    wire [7:0] uart_tx_data;
    wire       uart_tx_start;   // pulso: enviar byte
    wire       uart_tx_done;    // pulso: TX completado

    // --------------------------------------------------------
    // Wires debug_unit ↔ RISCV_Top
    // --------------------------------------------------------
    wire        debug_halt;
    wire        debug_step;
    wire        debug_cpu_rst;
    wire        halt_done;
    wire        debug_imem_we;
    wire [31:0] debug_imem_addr;
    wire [31:0] debug_imem_wdata;
    wire [4:0]  debug_rf_addr;
    wire [31:0] debug_rf_rdata;
    wire [31:0] debug_dmem_addr;
    wire [31:0] debug_dmem_wdata;
    wire        debug_dmem_we;
    wire [31:0] debug_dmem_rdata;
    // Latches de pipeline → debug_unit
    wire [31:0] dbg_ifid_pc,  dbg_ifid_pc4,   dbg_ifid_instr;
    wire [31:0] dbg_idex_pc,  dbg_idex_rs1,   dbg_idex_rs2;
    wire [31:0] dbg_idex_imm, dbg_idex_ctrl;
    wire [31:0] dbg_exmem_pc4, dbg_exmem_alu,  dbg_exmem_rs2;
    wire [31:0] dbg_exmem_btgt,dbg_exmem_ctrl;
    wire [31:0] dbg_memwb_pc4, dbg_memwb_alu,  dbg_memwb_mdata, dbg_memwb_ctrl;

    // --------------------------------------------------------
    // UART: 100 MHz, 9600 baud
    // --------------------------------------------------------
    UART #(
        .CLOCK_FREQ(100_000_000),
        .BAUD_RATE (9600)
    ) u_uart (
        .i_clk      (clk_50),
        .i_reset    (rst_sync),
        .rx         (rx),
        .tx         (tx),
        .data_in    (uart_tx_data),
        .data_out   (uart_rx_data),
        .data_ready (uart_rx_valid),
        .tx_start   (uart_tx_start),
        .tx_done    (uart_tx_done)
    );

    // --------------------------------------------------------
    // Debug Unit: interpreta protocolo y controla el CPU
    // --------------------------------------------------------
    debug_unit u_debug (
        .clk         (clk_50),
        .rst         (rst_sync),
        // UART
        .rx_data     (uart_rx_data),
        .rx_valid    (uart_rx_valid),
        .tx_data     (uart_tx_data),
        .tx_start    (uart_tx_start),
        .tx_done     (uart_tx_done),
        // Control del pipeline
        .cpu_halt    (debug_halt),
        .cpu_step    (debug_step),
        .cpu_rst     (debug_cpu_rst),
        .halt_done   (halt_done),
        // Escritura en imem
        .imem_we     (debug_imem_we),
        .imem_addr   (debug_imem_addr),
        .imem_wdata  (debug_imem_wdata),
        // Lectura de registros
        .rf_raddr    (debug_rf_addr),
        .rf_rdata    (debug_rf_rdata),
        // Acceso a memoria de datos
        .dmem_addr   (debug_dmem_addr),
        .dmem_wdata  (debug_dmem_wdata),
        .dmem_we     (debug_dmem_we),
        .dmem_re     (),
        .dmem_rdata  (debug_dmem_rdata),
        // Latches de pipeline
        .ifid_pc     (dbg_ifid_pc),
        .ifid_pc4    (dbg_ifid_pc4),
        .ifid_instr  (dbg_ifid_instr),
        .idex_pc     (dbg_idex_pc),
        .idex_rs1    (dbg_idex_rs1),
        .idex_rs2    (dbg_idex_rs2),
        .idex_imm    (dbg_idex_imm),
        .idex_ctrl   (dbg_idex_ctrl),
        .exmem_pc4   (dbg_exmem_pc4),
        .exmem_alu   (dbg_exmem_alu),
        .exmem_rs2   (dbg_exmem_rs2),
        .exmem_btgt  (dbg_exmem_btgt),
        .exmem_ctrl  (dbg_exmem_ctrl),
        .memwb_pc4   (dbg_memwb_pc4),
        .memwb_alu   (dbg_memwb_alu),
        .memwb_mdata (dbg_memwb_mdata),
        .memwb_ctrl  (dbg_memwb_ctrl)
    );

    // --------------------------------------------------------
    // Procesador RISC-V pipeline de 5 etapas
    // --------------------------------------------------------
    RISCV_Top u_cpu (
        .clk              (clk_50),
        .rst              (rst_sync || debug_cpu_rst),
        // WB (no usado en este top)
        .wb_result        (),
        .wb_rd            (),
        .wb_we            (),
        // Debug control
        .debug_halt       (debug_halt),
        .debug_step       (debug_step),
        .halt_done_out    (halt_done),
        // Debug imem
        .debug_imem_we    (debug_imem_we),
        .debug_imem_addr  (debug_imem_addr),
        .debug_imem_wdata (debug_imem_wdata),
        // Debug regfile
        .debug_rf_addr    (debug_rf_addr),
        .debug_rf_rdata   (debug_rf_rdata),
        // Debug dmem
        .debug_dmem_addr  (debug_dmem_addr),
        .debug_dmem_wdata (debug_dmem_wdata),
        .debug_dmem_we    (debug_dmem_we),
        .debug_dmem_rdata (debug_dmem_rdata),
        // Debug latches
        .dbg_ifid_pc      (dbg_ifid_pc),
        .dbg_ifid_pc4     (dbg_ifid_pc4),
        .dbg_ifid_instr   (dbg_ifid_instr),
        .dbg_idex_pc      (dbg_idex_pc),
        .dbg_idex_rs1     (dbg_idex_rs1),
        .dbg_idex_rs2     (dbg_idex_rs2),
        .dbg_idex_imm     (dbg_idex_imm),
        .dbg_idex_ctrl    (dbg_idex_ctrl),
        .dbg_exmem_pc4    (dbg_exmem_pc4),
        .dbg_exmem_alu    (dbg_exmem_alu),
        .dbg_exmem_rs2    (dbg_exmem_rs2),
        .dbg_exmem_btgt   (dbg_exmem_btgt),
        .dbg_exmem_ctrl   (dbg_exmem_ctrl),
        .dbg_memwb_pc4    (dbg_memwb_pc4),
        .dbg_memwb_alu    (dbg_memwb_alu),
        .dbg_memwb_mdata  (dbg_memwb_mdata),
        .dbg_memwb_ctrl   (dbg_memwb_ctrl)
    );

endmodule
