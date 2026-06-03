module debug_unit (
    input  wire        clk,
    input  wire        rst,

    // Interfaz con UART (bytes ya decodificados)
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,   // pulso 1 ciclo: byte recibido
    output reg  [7:0]  tx_data,
    output reg         tx_start,   // pulso 1 ciclo: iniciar TX
    input  wire        tx_done,    // pulso 1 ciclo: TX completado

    // Control del pipeline
    output reg         cpu_halt,   // 1 = pipeline congelado
    output reg         cpu_step,   // pulso 1 ciclo = avanzar un ciclo (halt debe ser 1)
    output reg         cpu_rst,    // pulso 1 ciclo = reset del procesador (PC=0)
    input  wire        halt_done,  // 1 = pipeline detenido por instrucción HALT

    // Puerto escritura memoria de instrucciones (IF_Stage)
    output reg  [31:0] imem_addr,
    output reg  [31:0] imem_wdata,
    output reg         imem_we,

    // Puerto lectura banco de registros (ID_Stage)
    output reg  [4:0]  rf_raddr,
    input  wire [31:0] rf_rdata,

    // Puerto acceso memoria de datos (MEM_Stage)
    output reg  [31:0] dmem_addr,
    output reg  [31:0] dmem_wdata,
    output reg         dmem_we,
    output reg         dmem_re,
    input  wire [31:0] dmem_rdata,

    // Latches de pipeline (solo lectura, para CMD_RD_IFID..MEMWB)
    input  wire [31:0] ifid_pc,
    input  wire [31:0] ifid_pc4,
    input  wire [31:0] ifid_instr,
    input  wire [31:0] idex_pc,
    input  wire [31:0] idex_rs1,
    input  wire [31:0] idex_rs2,
    input  wire [31:0] idex_imm,
    input  wire [31:0] idex_ctrl,
    input  wire [31:0] exmem_pc4,
    input  wire [31:0] exmem_alu,
    input  wire [31:0] exmem_rs2,
    input  wire [31:0] exmem_btgt,
    input  wire [31:0] exmem_ctrl,
    input  wire [31:0] memwb_pc4,
    input  wire [31:0] memwb_alu,
    input  wire [31:0] memwb_mdata,
    input  wire [31:0] memwb_ctrl
);

    // ----------------------------------------------------------------
    // Opcodes del protocolo
    // ----------------------------------------------------------------
    localparam CMD_HALT    = 8'h01;
    localparam CMD_RUN     = 8'h02;
    localparam CMD_STEP    = 8'h03;
    localparam CMD_LOAD    = 8'h04;   // addr(4B) + instr(4B)
    localparam CMD_RD_REG  = 8'h05;   // reg(1B)  → data(4B)
    localparam CMD_RD_MEM  = 8'h06;   // addr(4B) → data(4B)
    localparam CMD_WR_MEM  = 8'h07;   // addr(4B) + data(4B)
    localparam CMD_RESET   = 8'h08;   // reset PC=0, mantiene cpu_halt=1
    localparam CMD_RD_IFID  = 8'h09;  // → 12 B (PC, PC+4, INSTR)
    localparam CMD_RD_IDEX  = 8'h0A;  // → 20 B (PC, RS1, RS2, IMM, CTRL)
    localparam CMD_RD_EXMEM = 8'h0B;  // → 20 B (PC+4, ALU, RS2, BTGT, CTRL)
    localparam CMD_RD_MEMWB = 8'h0C;  // → 16 B (PC+4, ALU, MDATA, CTRL)

    localparam ACK  = 8'hAA;
    localparam NACK = 8'hEE;

    // ----------------------------------------------------------------
    // Estados de la máquina principal
    // ----------------------------------------------------------------
    localparam S_IDLE = 3'd0;  // esperando opcode
    localparam S_RECV = 3'd1;  // acumulando bytes de parámetros
    localparam S_EXEC = 3'd2;  // ejecutando la operación (1 ciclo)
    localparam S_WAIT = 3'd3;  // esperar 1 ciclo para lecturas (dato válido)
    localparam S_SEND = 3'd4;  // enviando bytes de respuesta

    reg [2:0]  state;
    reg [7:0]  cmd;
    reg [63:0] param_buf;      // acumula hasta 8 bytes de parámetros (MSB first)
    reg [3:0]  bytes_left;     // cuántos bytes de param faltan recibir

    reg [31:0] resp_data;      // palabra actual a enviar (MSB first)
    reg [2:0]  resp_cnt;       // bytes restantes en la palabra actual (4..0)
    reg        resp_word;      // 1 = respuesta de 4 bytes, 0 = solo ACK
    reg        is_read_cmd;    // necesita capturar dato asíncrono en S_WAIT
    reg        tx_busy_r;      // 1 = UART ocupada transmitiendo
    reg        step_req;      // solicitar pulso de cpu_step en el siguiente flanco
    reg        rst_req;       // solicitar pulso de cpu_rst en el siguiente flanco
 // Buffer multi-word para respuestas de latches (máx 4 palabras extra)
    reg [31:0] resp_buf [0:3];
    reg [2:0]  resp_word_rem;  // palabras adicionales pendientes en resp_buf
    reg [2:0]  resp_buf_rd;    // índice de lectura en resp_buf

    // ----------------------------------------------------------------
    // Máquina de estados
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state       <= S_IDLE;
            cpu_halt    <= 1'b0;
            cpu_step    <= 1'b0;
            cpu_rst     <= 1'b0;
            tx_start    <= 1'b0;
            tx_data     <= 8'h0;
            imem_we     <= 1'b0;
            imem_addr   <= 32'h0;
            imem_wdata  <= 32'h0;
            dmem_we     <= 1'b0;
            dmem_re     <= 1'b0;
            dmem_addr   <= 32'h0;
            dmem_wdata  <= 32'h0;
            rf_raddr    <= 5'h0;
            resp_cnt    <= 3'd0;
            resp_data   <= 32'h0;
            resp_word   <= 1'b0;
            is_read_cmd <= 1'b0;
            tx_busy_r   <= 1'b0;
            bytes_left    <= 4'd0;
            cmd           <= 8'h0;
            param_buf     <= 64'h0;
            resp_word_rem <= 3'd0;
            resp_buf_rd   <= 3'd0;
        end else begin
            // pulsos de 1 ciclo: limpiar por defecto
            tx_start <= 1'b0;
            // instrucción HALT en el pipeline: auto-halt para que CMD_STEP funcione
            if (halt_done) cpu_halt <= 1'b1;
            // generar pulso de cpu_step / cpu_rst a partir de las solicitudes
            cpu_step <= step_req;
            cpu_rst  <= rst_req;
            // limpiar solicitudes por defecto (si fueron tomadas, se limpiarán ahora)
            step_req <= 1'b0;
            rst_req  <= 1'b0;
            imem_we  <= 1'b0;
            dmem_we  <= 1'b0;
            dmem_re  <= 1'b0;

            // seguimiento de ocupación de la UART
            if (tx_start) tx_busy_r <= 1'b1;
            else if (tx_done) tx_busy_r <= 1'b0;

            case (state)

                // --------------------------------------------------
                S_IDLE: begin
                    if (rx_valid) begin
                        cmd       <= rx_data;
                        param_buf <= 64'b0;
                        case (rx_data)
                            CMD_HALT:   begin bytes_left <= 4'd0; state <= S_EXEC; end
                            CMD_RUN:    begin bytes_left <= 4'd0; state <= S_EXEC; end
                            CMD_STEP:   begin bytes_left <= 4'd0; state <= S_EXEC; end
                            CMD_LOAD:   begin bytes_left <= 4'd8; state <= S_RECV; end
                            CMD_RD_REG: begin bytes_left <= 4'd1; state <= S_RECV; end
                            CMD_RD_MEM: begin bytes_left <= 4'd4; state <= S_RECV; end
                            CMD_WR_MEM: begin bytes_left <= 4'd8; state <= S_RECV; end
                            CMD_RESET:   begin bytes_left <= 4'd0; state <= S_EXEC; end
                            CMD_RD_IFID: begin bytes_left <= 4'd0; state <= S_EXEC; end
                            CMD_RD_IDEX: begin bytes_left <= 4'd0; state <= S_EXEC; end
                            CMD_RD_EXMEM:begin bytes_left <= 4'd0; state <= S_EXEC; end
                            CMD_RD_MEMWB:begin bytes_left <= 4'd0; state <= S_EXEC; end
                            default:    begin
                                // comando desconocido: responder NACK
                                resp_data <= {24'h0, NACK};
                                resp_cnt  <= 3'd1;
                                state     <= S_SEND;
                            end
                        endcase
                    end
                end

                // --------------------------------------------------
                // Acumular bytes de parámetros (shift-in MSB first)
                // --------------------------------------------------
                S_RECV: begin
                    if (rx_valid) begin
                        param_buf  <= {param_buf[55:0], rx_data};
                        bytes_left <= bytes_left - 4'd1;
                        if (bytes_left == 4'd1)
                            state <= S_EXEC;
                    end
                end

                // --------------------------------------------------
                // Ejecutar la operación
                // --------------------------------------------------
                S_EXEC: begin
                    is_read_cmd   <= 1'b0;
                    resp_word_rem <= 3'd0;   // default: respuesta de 1 sola palabra
                    resp_buf_rd   <= 3'd0;
                    case (cmd)
                        CMD_HALT: begin
                            cpu_halt  <= 1'b1;
                            resp_data <= {24'h0, ACK};
                            resp_cnt  <= 3'd1;
                            state     <= S_SEND;
                        end
                        CMD_RUN: begin
                            cpu_halt  <= 1'b0;
                            resp_data <= {24'h0, ACK};
                            resp_cnt  <= 3'd1;
                            state     <= S_SEND;
                        end
                        CMD_STEP: begin
                            // solicitar pulso de cpu_step para el siguiente flanco
                            // (si ponemos cpu_step=1 aquí, el CPU no lo verá)
                            step_req  <= 1'b1;
                            resp_data <= {24'h0, ACK};
                            resp_cnt  <= 3'd1;
                            state     <= S_SEND;
                        end
                        CMD_LOAD: begin
                            // param_buf[63:32] = dirección, [31:0] = instrucción
                            imem_addr  <= param_buf[63:32];
                            imem_wdata <= param_buf[31:0];
                            imem_we    <= 1'b1;
                            resp_data  <= {24'h0, ACK};
                            resp_cnt   <= 3'd1;
                            state      <= S_SEND;
                        end
                        CMD_RD_REG: begin
                            rf_raddr    <= param_buf[4:0];
                            is_read_cmd <= 1'b1;
                            resp_cnt    <= 3'd4;
                            state       <= S_WAIT;
                        end
                        CMD_RD_MEM: begin
                            dmem_addr   <= param_buf[31:0];
                            dmem_re     <= 1'b1;
                            is_read_cmd <= 1'b1;
                            resp_cnt    <= 3'd4;
                            state       <= S_WAIT;
                        end
                        CMD_WR_MEM: begin
                            dmem_addr  <= param_buf[63:32];
                            dmem_wdata <= param_buf[31:0];
                            dmem_we    <= 1'b1;
                            resp_data  <= {24'h0, ACK};
                            resp_cnt   <= 3'd1;
                            state     <= S_SEND;
                        end
                        CMD_RESET: begin
                            // solicitar pulso de reset para el siguiente flanco
                            rst_req  <= 1'b1;
                            cpu_halt  <= 1'b1;
                            resp_data <= {24'h0, ACK};
                            resp_cnt  <= 3'd1;
                            state     <= S_SEND;
                        end
                        // ── Lectura de latches (multi-word) ──────────
                        CMD_RD_IFID: begin
                            resp_data     <= ifid_pc;
                            resp_buf[0]   <= ifid_pc4;
                            resp_buf[1]   <= ifid_instr;
                            resp_word_rem <= 3'd2;
                            resp_cnt      <= 3'd4;
                            state         <= S_SEND;
                        end
                        CMD_RD_IDEX: begin
                            resp_data     <= idex_pc;
                            resp_buf[0]   <= idex_rs1;
                            resp_buf[1]   <= idex_rs2;
                            resp_buf[2]   <= idex_imm;
                            resp_buf[3]   <= idex_ctrl;
                            resp_word_rem <= 3'd4;
                            resp_cnt      <= 3'd4;
                            state         <= S_SEND;
                        end
                        CMD_RD_EXMEM: begin
                            resp_data     <= exmem_pc4;
                            resp_buf[0]   <= exmem_alu;
                            resp_buf[1]   <= exmem_rs2;
                            resp_buf[2]   <= exmem_btgt;
                            resp_buf[3]   <= exmem_ctrl;
                            resp_word_rem <= 3'd4;
                            resp_cnt      <= 3'd4;
                            state         <= S_SEND;
                        end
                        CMD_RD_MEMWB: begin
                            resp_data     <= memwb_pc4;
                            resp_buf[0]   <= memwb_alu;
                            resp_buf[1]   <= memwb_mdata;
                            resp_buf[2]   <= memwb_ctrl;
                            resp_word_rem <= 3'd3;
                            resp_cnt      <= 3'd4;
                            state         <= S_SEND;
                        end
                        default: begin
                            resp_data <= {24'h0, NACK};
                            resp_cnt  <= 3'd1;
                            state     <= S_SEND;
                        end
                    endcase
                end

                // --------------------------------------------------
                // Capturar dato de lectura (1 ciclo de latencia)
                // --------------------------------------------------
                S_WAIT: begin
                    case (cmd)
                        CMD_RD_REG: resp_data <= rf_rdata;
                        CMD_RD_MEM: resp_data <= dmem_rdata;
                        default:;
                    endcase
                    state <= S_SEND;
                end

                // --------------------------------------------------
                // Enviar bytes de respuesta (MSB first)
                // Soporta múltiples palabras de 32 bits (latches)
                // --------------------------------------------------
                S_SEND: begin
                    // enviar siguiente byte cuando la UART esté libre
                    if (resp_cnt > 3'd0 && !tx_busy_r && !tx_start) begin
                        case (resp_cnt)
                            3'd4: tx_data <= resp_data[31:24];
                            3'd3: tx_data <= resp_data[23:16];
                            3'd2: tx_data <= resp_data[15:8];
                            3'd1: tx_data <= resp_data[7:0];
                            default:;
                        endcase
                        tx_start <= 1'b1;
                        resp_cnt <= resp_cnt - 3'd1;
                    end

                    // al terminar la palabra actual: cargar la siguiente o ir a IDLE
                    if (resp_cnt == 3'd0 && tx_done) begin
                        if (resp_word_rem > 3'd0) begin
                            case (resp_buf_rd)
                                3'd0: resp_data <= resp_buf[0];
                                3'd1: resp_data <= resp_buf[1];
                                3'd2: resp_data <= resp_buf[2];
                                3'd3: resp_data <= resp_buf[3];
                                default: resp_data <= 32'h0;
                            endcase
                            resp_buf_rd   <= resp_buf_rd + 3'd1;
                            resp_word_rem <= resp_word_rem - 3'd1;
                            resp_cnt      <= 3'd4;
                        end else
                            state <= S_IDLE;
                    end
                end

            endcase
        end
    end

endmodule
