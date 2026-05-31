module ID_Stage (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] pc, // conservo el PC en ID para usarlo en AUIPC y generación de branch targets
    input  wire [31:0] pc_plus4,
    input  wire [31:0] instruction,
    // Puerto de escritura desde WB
    input  wire [4:0]  wb_rd_addr, // dirección de destino del write-back
    input  wire [31:0] wb_write_data, // dato a escribir en el banco de registros
    input  wire        wb_reg_write, // señal de control: 1 si WB va a escribir en el banco de registros
    // Salidas de datos
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    output wire [31:0] imm,
    output wire [4:0]  rs1_addr,
    output wire [4:0]  rs2_addr,
    output wire [4:0]  rd_addr,
    // Señales de control
    output reg  [3:0]  alu_op,
    output reg         alu_src,
    output reg         mem_read,
    output reg         mem_write,
    output reg         reg_write,
    output reg         mem_to_reg,
    output reg         branch,
    output reg         jump,
    // Puerto de lectura para debug unit
    input  wire [4:0]  debug_rf_addr, // dirección de registro a leer para debug
    output wire [31:0] debug_rf_rdata // dato leído del banco de registros para debug
);

    // ----------------------------------------------------------
    // Banco de registros: 32 registros de 32 bits
    // x0 está cableado a 0 por hardware
    // ----------------------------------------------------------
    reg [31:0] regs [0:31];

    // Decodificación de campos de la instrucción
    wire [6:0] opcode = instruction[6:0];
    wire [2:0] funct3 = instruction[14:12];
    wire [6:0] funct7 = instruction[31:25];

    assign rs1_addr = instruction[19:15];
    assign rs2_addr = instruction[24:20];
    assign rd_addr  = instruction[11:7];

    // ----------------------------------------------------------
    // Lectura del banco de registros (asíncrona)
    // Write-first: si WB está escribiendo en este ciclo y las
    // direcciones coinciden, se usa el valor nuevo directamente
    // ----------------------------------------------------------
    wire [31:0] rs1_raw = (rs1_addr == 5'b0) ? 32'b0 : regs[rs1_addr];
    wire [31:0] rs2_raw = (rs2_addr == 5'b0) ? 32'b0 : regs[rs2_addr];

    wire fwd_rs1 = wb_reg_write && (wb_rd_addr != 5'b0) && (wb_rd_addr == rs1_addr);
    wire fwd_rs2 = wb_reg_write && (wb_rd_addr != 5'b0) && (wb_rd_addr == rs2_addr);

    wire [31:0] rs1_base = fwd_rs1 ? wb_write_data : rs1_raw;
    wire [31:0] rs2_base = fwd_rs2 ? wb_write_data : rs2_raw;

    // AUIPC necesita PC como operando A en la ALU
    assign rs1_data = (opcode == 7'b0010111) ? pc : rs1_base;
    assign rs2_data = rs2_base;

    // ----------------------------------------------------------
    // Escritura síncrona en el banco de registros (desde WB)
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (wb_reg_write && wb_rd_addr != 5'b0)
            regs[wb_rd_addr] <= wb_write_data;
    end

    // ----------------------------------------------------------
    // Generador de inmediato (extensión de signo)
    // ----------------------------------------------------------
    reg [31:0] imm_r;
    always @(*) begin
        case (opcode)
            7'b0010011,          // I-type ALU (ADDI, SLTI, ...)
            7'b0000011,          // Load (LW, LH, LB, ...)
            7'b1100111:          // JALR
                imm_r = {{20{instruction[31]}}, instruction[31:20]};

            7'b0100011:          // S-type (SW, SH, SB)
                imm_r = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};

            7'b1100011:          // B-type (BEQ, BNE, BLT, ...)
                imm_r = {{19{instruction[31]}}, instruction[31],
                          instruction[7], instruction[30:25], instruction[11:8], 1'b0};

            7'b0110111,          // LUI
            7'b0010111:          // AUIPC
                imm_r = {instruction[31:12], 12'b0};

            7'b1101111:          // J-type (JAL)
                imm_r = {{11{instruction[31]}}, instruction[31],
                          instruction[19:12], instruction[20], instruction[30:21], 1'b0};

            default: imm_r = 32'b0;
        endcase
    end
    assign imm = imm_r;

    assign debug_rf_rdata = (debug_rf_addr == 5'b0) ? 32'b0 : regs[debug_rf_addr];


    // En esta seccion combinacional se asignan valores por defecto a las señales de control
    // y luego se sobreescriben según el opcode (y a veces funct3/funct7) de la instrucción. Si el opcode no coincide con ningún caso, se mantiene el
    // valor por defecto, que corresponde a una operación NOP (no hace nada).  
    // ----Codificación de branch/jump---:
    //   branch=0, jump=0: instrucción normal
    //   branch=1, jump=0: B-type branch
    //   branch=0, jump=1: JAL
    //   branch=1, jump=1: JALR 
    always @(*) begin
        // Valores por defecto  de una operacion NOP
        alu_op    = 4'b0000;
        alu_src   = 1'b0;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        reg_write = 1'b0;
        mem_to_reg= 1'b0;
        branch    = 1'b0;
        jump      = 1'b0;

        case (opcode)
            // --------------------------------------------------
            7'b0110011: begin // R-type (ADD, SUB, SLL, SLT, ...)
                reg_write = 1'b1;
                case (funct3)
                    3'b000: alu_op = funct7[5] ? 4'b0001 : 4'b0000; // SUB / ADD
                    3'b001: alu_op = 4'b0010; // SLL
                    3'b010: alu_op = 4'b0011; // SLT
                    3'b011: alu_op = 4'b0100; // SLTU
                    3'b100: alu_op = 4'b0101; // XOR
                    3'b101: alu_op = funct7[5] ? 4'b0111 : 4'b0110; // SRA / SRL
                    3'b110: alu_op = 4'b1000; // OR
                    3'b111: alu_op = 4'b1001; // AND
                    default: alu_op = 4'b0000;
                endcase
            end
            // --------------------------------------------------
            7'b0010011: begin // I-type ALU 
                reg_write = 1'b1;
                alu_src   = 1'b1;
                case (funct3)
                    3'b000: alu_op = 4'b0000; // ADDI
                    3'b001: alu_op = 4'b0010; // SLLI
                    3'b010: alu_op = 4'b0011; // SLTI
                    3'b011: alu_op = 4'b0100; // SLTIU
                    3'b100: alu_op = 4'b0101; // XORI
                    3'b101: alu_op = funct7[5] ? 4'b0111 : 4'b0110; // SRAI / SRLI
                    3'b110: alu_op = 4'b1000; // ORI
                    3'b111: alu_op = 4'b1001; // ANDI
                    default: alu_op = 4'b0000;
                endcase
            end
            // --------------------------------------------------
            7'b0000011: begin // Load (LW, LH, LB, LHU, LBU)
                reg_write  = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
                alu_src    = 1'b1;   // dirección = rs1 + imm, en el libro, revisar
                alu_op     = 4'b0000;
            end
            // --------------------------------------------------
            7'b0100011: begin // Store (SW, SH, SB)
                mem_write = 1'b1;
                alu_src   = 1'b1;    // dirección = rs1 + imm
                alu_op    = 4'b0000;
            end
            // --------------------------------------------------
            7'b1100011: begin // Branch (BEQ, BNE, BLT, BGE, BLTU, BGEU)
                branch = 1'b1;
                // funct3 codifica el tipo de comparación en la ALU
                alu_op = {1'b0, funct3};
            end
            // --------------------------------------------------
            7'b1101111: begin // JAL
                reg_write = 1'b1;
                jump      = 1'b1;
                // alu_result será overrideado a PC+4 en EX
            end
            // --------------------------------------------------
            7'b1100111: begin // JALR
                reg_write = 1'b1;
                alu_src   = 1'b1;    // dirección = rs1 + imm
                branch    = 1'b1;    // branch=1 + jump=1 → modo JALR
                jump      = 1'b1;
                alu_op    = 4'b0000; // ADD: rs1 + imm
            end
            // --------------------------------------------------
            7'b0110111: begin // LUI
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 4'b1010; // PASSB: resultado = inmediato
            end
            // --------------------------------------------------
            7'b0010111: begin // AUIPC
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 4'b0000; // ADD: PC + imm (PC enviado como rs1_data)
            end
            // --------------------------------------------------
            default: begin
                // Instrucción desconocida: NOP (no hace nada)
            end
        endcase
    end

endmodule
