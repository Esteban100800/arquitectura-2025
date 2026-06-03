// ============================================================
// EX_Stage.v  -  Execute (ALU + Forwarding + Branch)
// Pipeline RISC-V de 5 etapas: IF | ID | EX | MEM | WB
//
// Codificación de branch/jump:
//   branch=0, jump=0  →  instrucción normal
//   branch=1, jump=0  →  B-type  (target = PC + imm)
//   branch=0, jump=1  →  JAL     (target = PC + imm, resultado = PC+4)
//   branch=1, jump=1  →  JALR    (target = (rs1+imm)&~1, resultado = PC+4)
//
// Forwarding (fwd_a / fwd_b):
//   2'b00  →  sin forwarding (usar registro)
//   2'b01  →  MEM/WB  (resultado de 2 ciclos atrás)
//   2'b10  →  EX/MEM  (resultado del ciclo anterior)
// ============================================================
module EX_Stage (
    input  wire        clk,           // No usado internamente (etapa combinacional)
    input  wire [31:0] pc,
    input  wire [31:0] pc_plus4,
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [31:0] imm,
    input  wire [4:0]  rd_addr,
    input  wire [3:0]  alu_op,
    input  wire        alu_src,       // 0=rs2, 1=imm
    input  wire        branch,
    input  wire        jump,
    // Forwarding
    input  wire [1:0]  fwd_a,
    input  wire [1:0]  fwd_b,
    input  wire [31:0] fwd_ex_mem,    // Dato desde registro EX/MEM (1 ciclo atrás)
    input  wire [31:0] fwd_mem_wb,    // Dato desde registro MEM/WB (2 ciclos atrás)
    // Salidas
    output wire [31:0] alu_result,    // Resultado final (PC+4 para JAL/JALR)
    output wire [31:0] rs2_forwarded, // rs2 después de forwarding (para stores)
    output wire        zero,          // Flag zero de la ALU
    output wire        branch_taken,  // Indica si se toma el salto
    output wire [31:0] branch_target  // Dirección destino del salto
);

    // ----------------------------------------------------------
    // Mux de forwarding para operando A (rs1)
    // ----------------------------------------------------------
    reg [31:0] op_a;
    always @(*) begin
        case (fwd_a)
            2'b10:   op_a = fwd_ex_mem;
            2'b01:   op_a = fwd_mem_wb;
            default: op_a = rs1_data;
        endcase
    end

    // ----------------------------------------------------------
    // Mux de forwarding para operando B (rs2)
    // rs2_forwarded se usa para el dato de escritura en stores
    // alu_op_b puede ser el inmediato si alu_src=1
    // ----------------------------------------------------------
    reg [31:0] op_b_fwd;
    always @(*) begin
        case (fwd_b)
            2'b10:   op_b_fwd = fwd_ex_mem;
            2'b01:   op_b_fwd = fwd_mem_wb;
            default: op_b_fwd = rs2_data;
        endcase
    end

    assign rs2_forwarded = op_b_fwd;

    // Operando B de la ALU: inmediato o rs2 con forwarding
    wire [31:0] alu_op_b = alu_src ? imm : op_b_fwd;

    // ----------------------------------------------------------
    // Instancia de la ALU (módulo ALU.v)
    // ----------------------------------------------------------
    wire [31:0] alu_comp;

    ALU u_alu (
        .op_a   (op_a),
        .op_b   (alu_op_b),
        .alu_op (alu_op),
        .result (alu_comp),
        .zero   (zero)
    );

    // Para JAL/JALR: alu_result = PC+4 (valor de enlace a escribir en rd)
    // Para el resto:  alu_result = resultado de la ALU
    assign alu_result = jump ? pc_plus4 : alu_comp;

    // ----------------------------------------------------------
    // Comparador de branch (usa alu_op[2:0] = funct3 del branch)
    // ----------------------------------------------------------
    reg compare_result;
    always @(*) begin
        case (alu_op[2:0])
            3'b000: compare_result = (op_a == op_b_fwd);                        // BEQ
            3'b001: compare_result = (op_a != op_b_fwd);                        // BNE
            3'b100: compare_result = ($signed(op_a) < $signed(op_b_fwd));       // BLT
            3'b101: compare_result = ($signed(op_a) >= $signed(op_b_fwd));      // BGE
            3'b110: compare_result = (op_a < op_b_fwd);                         // BLTU
            3'b111: compare_result = (op_a >= op_b_fwd);                        // BGEU
            default: compare_result = 1'b0;
        endcase
    end

    // jump siempre se toma; branch se toma si la comparación es verdadera
    assign branch_taken = jump || (branch && compare_result);

    // ----------------------------------------------------------
    // Cálculo del PC destino
    //   JALR  (branch=1, jump=1): (rs1 + imm) con LSB = 0
    //   JAL   (branch=0, jump=1): PC + imm
    //   B-type (branch=1, jump=0): PC + imm
    // ----------------------------------------------------------
    assign branch_target = (branch && jump)
                           ? {alu_comp[31:1], 1'b0}   // JALR: (rs1+imm)&~1
                           : (pc + imm);               // JAL o B-type: PC+imm

endmodule
