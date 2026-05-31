// ============================================================
// RISCV_Top.v  -  Top Module del procesador RISC-V pipeline
// Pipeline de 5 etapas: IF | ID | EX | MEM | WB
//
// Este módulo NO tiene lógica propia. Solo instancia y conecta
// todas las etapas y registros de pipeline mediante wires.
// ============================================================
module RISCV_Top (
    input  wire        clk,
    input  wire        rst,
    // Señales WB expuestas para uso en síntesis (ej: LEDs)
    output wire [31:0] wb_result,
    output wire [4:0]  wb_rd,
    output wire        wb_we,
    // Puerto debug: control
    input  wire        debug_halt,     // 1 = congelar todo el pipeline
    input  wire        debug_step,     // pulso = avanzar 1 ciclo
    // Puerto debug: escritura en imem (va a IF_Stage / BRAM Port A)
    input  wire        debug_imem_we,
    input  wire [31:0] debug_imem_addr,
    input  wire [31:0] debug_imem_wdata,
    // Puerto debug: lectura del banco de registros
    input  wire [4:0]  debug_rf_addr,
    output wire [31:0] debug_rf_rdata,
    // Puerto debug: acceso a memoria de datos
    input  wire [31:0] debug_dmem_addr,
    input  wire [31:0] debug_dmem_wdata,
    input  wire        debug_dmem_we,
    output wire [31:0] debug_dmem_rdata,
    // Puerto debug: salidas de latches de pipeline (palabras pre-empaquetadas)
    output wire [31:0] dbg_ifid_pc,
    output wire [31:0] dbg_ifid_pc4,
    output wire [31:0] dbg_ifid_instr,
    output wire [31:0] dbg_idex_pc,
    output wire [31:0] dbg_idex_rs1,
    output wire [31:0] dbg_idex_rs2,
    output wire [31:0] dbg_idex_imm,
    output wire [31:0] dbg_idex_ctrl,
    output wire [31:0] dbg_exmem_pc4,
    output wire [31:0] dbg_exmem_alu,
    output wire [31:0] dbg_exmem_rs2,
    output wire [31:0] dbg_exmem_btgt,
    output wire [31:0] dbg_exmem_ctrl,
    output wire [31:0] dbg_memwb_pc4,
    output wire [31:0] dbg_memwb_alu,
    output wire [31:0] dbg_memwb_mdata,
    output wire [31:0] dbg_memwb_ctrl,
    // Pipeline detenido por instrucción HALT (para debug_unit)
    output wire        halt_done_out
);

    // ==========================================================
    // WIRES entre IF y el registro IF/ID
    // ==========================================================
    wire [31:0] if_pc;
    wire [31:0] if_pc_plus4;
    wire [31:0] if_instruction;

    // ==========================================================
    // WIRES entre el registro IF/ID y la etapa ID
    // ==========================================================
    wire [31:0] id_pc;
    wire [31:0] id_pc_plus4;
    wire [31:0] id_instruction;

    // ==========================================================
    // WIRES entre la etapa ID y el registro ID/EX
    // (señales de control + datos decodificados)
    // ==========================================================
    wire [31:0] id_rs1_data;       // Valor leído del registro rs1
    wire [31:0] id_rs2_data;       // Valor leído del registro rs2
    wire [31:0] id_imm;            // Inmediato extendido en signo
    wire [4:0]  id_rs1_addr;       // Dirección de rs1 (para forwarding)
    wire [4:0]  id_rs2_addr;       // Dirección de rs2 (para forwarding)
    wire [4:0]  id_rd_addr;        // Dirección del registro destino
    wire [3:0]  id_alu_op;         // Operación ALU
    wire        id_alu_src;        // 0=rs2, 1=inmediato
    wire        id_mem_read;       // Lectura de memoria (LW)
    wire        id_mem_write;      // Escritura en memoria (SW)
    wire        id_reg_write;      // Escritura en banco de registros
    wire        id_mem_to_reg;     // 0=ALU, 1=memoria → registro destino
    wire        id_branch;         // Instrucción de branch
    wire        id_jump;           // Instrucción de jump (JAL/JALR)

    // ==========================================================
    // WIRES entre el registro ID/EX y la etapa EX
    // ==========================================================
    wire [31:0] ex_pc;
    wire [31:0] ex_pc_plus4;
    wire [31:0] ex_rs1_data;
    wire [31:0] ex_rs2_data;
    wire [31:0] ex_imm;
    wire [4:0]  ex_rs1_addr;
    wire [4:0]  ex_rs2_addr;
    wire [4:0]  ex_rd_addr;
    wire [3:0]  ex_alu_op;
    wire        ex_alu_src;
    wire        ex_mem_read;
    wire        ex_mem_write;
    wire        ex_reg_write;
    wire        ex_mem_to_reg;
    wire        ex_branch;
    wire        ex_jump;

    // ==========================================================
    // WIRES de salida de la etapa EX
    // ==========================================================
    wire [31:0] ex_alu_result;     // Resultado de la ALU
    wire [31:0] ex_rs2_fwd;        // rs2 después del forwarding (dato a escribir en MEM)
    wire        ex_zero;           // Flag zero de la ALU (para branches)
    wire        ex_branch_taken;   // Branch/jump efectivamente tomado (combinacional)
    wire [31:0] ex_branch_target;  // Dirección destino del salto (combinacional)

    // Branch registrado en EX/MEM — estos van a IF y Hazard_Unit
    wire        mem_branch_taken;
    wire [31:0] mem_branch_target;

    // ==========================================================
    // WIRES entre el registro EX/MEM y la etapa MEM
    // ==========================================================
    wire [31:0] mem_pc_plus4;
    wire [31:0] mem_alu_result;
    wire [31:0] mem_rs2_data;
    wire [4:0]  mem_rd_addr;
    wire        mem_mem_read;
    wire        mem_mem_write;
    wire        mem_reg_write;
    wire        mem_mem_to_reg;

    // ==========================================================
    // WIRES de salida de la etapa MEM
    // ==========================================================
    wire [31:0] mem_read_data;     // Dato leído de la memoria de datos

    // ==========================================================
    // WIRES entre el registro MEM/WB y la etapa WB
    // ==========================================================
    wire [31:0] wb_pc_plus4;
    wire [31:0] wb_alu_result;
    wire [31:0] wb_mem_data;
    wire [4:0]  wb_rd_addr;
    wire        wb_reg_write;
    wire        wb_mem_to_reg;

    // ==========================================================
    // WIRES de salida de la etapa WB (van de vuelta a ID)
    // ==========================================================
    wire [31:0] wb_write_data;     // Dato a escribir en el banco de registros

    // ==========================================================
    // WIRES de control de hazards
    // ==========================================================
    wire        stall;             // Generado por Hazard Unit → detiene IF e ID
    wire        if_id_flush;       // Limpia el registro IF/ID (branch tomado)
    wire        id_ex_flush;       // Limpia el registro ID/EX (branch tomado)

    // debug_freeze: congela TODO el pipeline cuando debug_halt=1 y no hay step
    wire        debug_freeze = debug_halt && !debug_step;
    // flush del registro EX/MEM cuando branch tomado (viene de Hazard_Unit)
    wire        ex_mem_flush;

    // ── Halt Detection Unit ────────────────────────────────────────
    // Detecta opcode 1111111 (HALT) en id_instruction y drena el pipeline
    wire        halt_instr     = (id_instruction[6:0] == 7'b1111111);
    wire        hdu_flush_if_id;
    wire        hdu_freeze_if;
    wire        hdu_stall_if_id;
    wire        hdu_freeze_all;
    wire        halt_done;

    // resume: CMD_STEP mientras el HDU está halteado (breakpoint step-through)
    //         ó flanco descendente de debug_halt mientras halt_done=1
    //         (flujo CMD_HALT → inspección → CMD_RUN)
    reg  debug_halt_d;
    always @(posedge clk or posedge rst) begin
        if (rst) debug_halt_d <= 1'b0;
        else     debug_halt_d <= debug_halt;
    end
    // resume solo cuando el pipeline ya drenó (halt_done=1)
    // debug_step mientras halt_done → step-through del breakpoint
    // flanco bajante de debug_halt mientras halt_done → CMD_HALT+CMD_RUN
    wire hdu_resume = (debug_step && halt_done) || (debug_halt_d && !debug_halt && halt_done);

    // HDU FSM solo avanza cuando el pipeline puede avanzar
    // (debug_freeze=1 entre steps → HDU no cuenta; debug_step=1 → sí cuenta)
    wire hdu_clk_en    = !debug_freeze;
    // Si un branch se toma mientras HDU está drenando, el HALT era especulativo.
    // Se cancela el drain y se vuelve a IDLE para no detener el pipeline.
    wire hdu_cancel    = mem_branch_taken;

    halt_detection_unit u_hdu (
        .clk        (clk),
        .rst        (rst),
        .halt_instr (halt_instr),
        .resume     (hdu_resume),
        .clk_en     (hdu_clk_en),
        .cancel     (hdu_cancel),
        .flush_if_id(hdu_flush_if_id),
        .freeze_if  (hdu_freeze_if),
        .stall_if_id(hdu_stall_if_id),
        .freeze_all (hdu_freeze_all),
        .halt_done  (halt_done)
    );
    assign halt_done_out = halt_done;

    // En HALTED+resume, las tres señales de freeze se liberan en el mismo ciclo:
    //   - hdu_freeze_if  → stall_full      → PC avanza
    //   - hdu_stall_if_id→ stall_if_id_full→ IF/ID captura la instrucción
    //   - hdu_freeze_all → freeze_pipeline → ID/EX..MEM/WB avanzan
    // Así PC, IF/ID y el resto se mueven juntos, sin saltar instrucciones.
    wire        stall_full       = stall || debug_freeze || (hdu_freeze_if && !hdu_resume);
    wire        stall_if_id_full = stall_full || (hdu_stall_if_id && !hdu_resume);
    wire        freeze_pipeline  = debug_freeze || (hdu_freeze_all && !hdu_resume);

    // Flush signals gateados: no deben dispararse mientras el pipeline está
    // congelado en modo debug. Sin este gate, el primer ciclo congelado tras
    // un branch/jump limpia EX/MEM (borra branch_taken) y el redirect del PC
    // se pierde antes de que el usuario envíe el siguiente CMD_STEP.
    wire        if_id_flush_g  = (if_id_flush || hdu_flush_if_id) && !debug_freeze;
    wire        id_ex_flush_g  = id_ex_flush  && !debug_freeze;
    wire        ex_mem_flush_g = ex_mem_flush && !debug_freeze;

    // ==========================================================
    // WIRES de forwarding (de la Forwarding Unit hacia EX)
    // ==========================================================
    wire [1:0]  fwd_a;             // Selector forward para operando A de la ALU
    wire [1:0]  fwd_b;             // Selector forward para operando B de la ALU

    // ----------------------------------------------------------
    // INSTANCIA 1: Etapa IF
    // ----------------------------------------------------------
    IF_Stage u_if (
        .clk            (clk),
        .rst            (rst),
        .stall          (stall_full),
        .branch_taken   (mem_branch_taken),
        .branch_target  (mem_branch_target),
        .pc             (if_pc),
        .instruction    (if_instruction),
        .pc_plus4       (if_pc_plus4),
        .debug_we       (debug_imem_we),
        .debug_addr     (debug_imem_addr),
        .debug_wdata    (debug_imem_wdata)
    );

    // ----------------------------------------------------------
    // INSTANCIA 2: Registro de pipeline IF/ID
    // ----------------------------------------------------------
    IF_ID_Reg u_if_id (
        .clk            (clk),
        .rst            (rst),
        .stall          (stall_if_id_full),
        .flush          (if_id_flush_g),
        .if_pc          (if_pc),
        .if_pc_plus4    (if_pc_plus4),
        .if_instruction (if_instruction),
        .id_pc          (id_pc),
        .id_pc_plus4    (id_pc_plus4),
        .id_instruction (id_instruction)
    );

    // ----------------------------------------------------------
    // INSTANCIA 3: Etapa ID (Decodificación + Banco de Registros)
    // ----------------------------------------------------------
    ID_Stage u_id (
        .clk           (clk),
        .rst           (rst),
        .pc            (id_pc),
        .pc_plus4      (id_pc_plus4),
        .instruction   (id_instruction),
        // Write-back (desde WB)
        .wb_rd_addr    (wb_rd_addr),
        .wb_write_data (wb_write_data),
        .wb_reg_write  (wb_reg_write),
        // Salidas de datos
        .rs1_data      (id_rs1_data),
        .rs2_data      (id_rs2_data),
        .imm           (id_imm),
        .rs1_addr      (id_rs1_addr),
        .rs2_addr      (id_rs2_addr),
        .rd_addr       (id_rd_addr),
        // Señales de control
        .alu_op        (id_alu_op),
        .alu_src       (id_alu_src),
        .mem_read      (id_mem_read),
        .mem_write     (id_mem_write),
        .reg_write     (id_reg_write),
        .mem_to_reg    (id_mem_to_reg),
        .branch        (id_branch),
        .jump          (id_jump),
        // Debug
        .debug_rf_addr (debug_rf_addr),
        .debug_rf_rdata(debug_rf_rdata)
    );

    // ----------------------------------------------------------
    // INSTANCIA 4: Registro de pipeline ID/EX
    // ----------------------------------------------------------
    ID_EX_Reg u_id_ex (
        .clk          (clk),
        .rst          (rst),
        .flush        (id_ex_flush_g),
        .freeze       (freeze_pipeline),
        .in_pc        (id_pc),
        .in_pc_plus4  (id_pc_plus4),
        .in_rs1_data  (id_rs1_data),
        .in_rs2_data  (id_rs2_data),
        .in_imm       (id_imm),
        .in_rs1_addr  (id_rs1_addr),
        .in_rs2_addr  (id_rs2_addr),
        .in_rd_addr   (id_rd_addr),
        .in_alu_op    (id_alu_op),
        .in_alu_src   (id_alu_src),
        .in_mem_read  (id_mem_read),
        .in_mem_write (id_mem_write),
        .in_reg_write (id_reg_write),
        .in_mem_to_reg(id_mem_to_reg),
        .in_branch    (id_branch),
        .in_jump      (id_jump),
        .out_pc       (ex_pc),
        .out_pc_plus4 (ex_pc_plus4),
        .out_rs1_data (ex_rs1_data),
        .out_rs2_data (ex_rs2_data),
        .out_imm      (ex_imm),
        .out_rs1_addr (ex_rs1_addr),
        .out_rs2_addr (ex_rs2_addr),
        .out_rd_addr  (ex_rd_addr),
        .out_alu_op   (ex_alu_op),
        .out_alu_src  (ex_alu_src),
        .out_mem_read (ex_mem_read),
        .out_mem_write(ex_mem_write),
        .out_reg_write(ex_reg_write),
        .out_mem_to_reg(ex_mem_to_reg),
        .out_branch   (ex_branch),
        .out_jump     (ex_jump)
    );

    // ----------------------------------------------------------
    // INSTANCIA 5: Etapa EX (ALU + cálculo de branch)
    // ----------------------------------------------------------
    EX_Stage u_ex (
        .clk           (clk),
        .pc            (ex_pc),
        .pc_plus4      (ex_pc_plus4),
        .rs1_data      (ex_rs1_data),
        .rs2_data      (ex_rs2_data),
        .imm           (ex_imm),
        .rd_addr       (ex_rd_addr),
        .alu_op        (ex_alu_op),
        .alu_src       (ex_alu_src),
        .branch        (ex_branch),
        .jump          (ex_jump),
        // Forwarding
        .fwd_a         (fwd_a),
        .fwd_b         (fwd_b),
        .fwd_ex_mem    (mem_alu_result),
        .fwd_mem_wb    (wb_write_data),
        // Salidas
        .alu_result    (ex_alu_result),
        .rs2_forwarded (ex_rs2_fwd),
        .zero          (ex_zero),
        .branch_taken  (ex_branch_taken),
        .branch_target (ex_branch_target)
    );

    // ----------------------------------------------------------
    // INSTANCIA 6: Registro de pipeline EX/MEM
    // ----------------------------------------------------------
    EX_MEM_Reg u_ex_mem (
        .clk              (clk),
        .rst              (rst),
        .freeze           (freeze_pipeline),
        .flush            (ex_mem_flush_g),
        .in_pc_plus4      (ex_pc_plus4),
        .in_alu_result    (ex_alu_result),
        .in_rs2_data      (ex_rs2_fwd),
        .in_rd_addr       (ex_rd_addr),
        .in_mem_read      (ex_mem_read),
        .in_mem_write     (ex_mem_write),
        .in_reg_write     (ex_reg_write),
        .in_mem_to_reg    (ex_mem_to_reg),
        .in_branch_taken  (ex_branch_taken),
        .in_branch_target (ex_branch_target),
        .out_pc_plus4     (mem_pc_plus4),
        .out_alu_result   (mem_alu_result),
        .out_rs2_data     (mem_rs2_data),
        .out_rd_addr      (mem_rd_addr),
        .out_mem_read     (mem_mem_read),
        .out_mem_write    (mem_mem_write),
        .out_reg_write    (mem_reg_write),
        .out_mem_to_reg   (mem_mem_to_reg),
        .out_branch_taken (mem_branch_taken),
        .out_branch_target(mem_branch_target)
    );

    // ----------------------------------------------------------
    // INSTANCIA 7: Etapa MEM (Memoria de datos)
    // ----------------------------------------------------------
    MEM_Stage u_mem (
        .clk         (clk),
        .mem_read    (mem_mem_read),
        .mem_write   (mem_mem_write),
        .address     (mem_alu_result),
        .write_data  (mem_rs2_data),
        .read_data   (mem_read_data),
        // Debug
        .debug_addr  (debug_dmem_addr),
        .debug_wdata (debug_dmem_wdata),
        .debug_we    (debug_dmem_we),
        .debug_rdata (debug_dmem_rdata)
    );

    // ----------------------------------------------------------
    // INSTANCIA 8: Registro de pipeline MEM/WB
    // ----------------------------------------------------------
    MEM_WB_Reg u_mem_wb (
        .clk           (clk),
        .rst           (rst),
        .freeze        (freeze_pipeline),
        .in_pc_plus4   (mem_pc_plus4),
        .in_alu_result (mem_alu_result),
        .in_mem_data   (mem_read_data),
        .in_rd_addr    (mem_rd_addr),
        .in_reg_write  (mem_reg_write),
        .in_mem_to_reg (mem_mem_to_reg),
        .out_pc_plus4  (wb_pc_plus4),
        .out_alu_result(wb_alu_result),
        .out_mem_data  (wb_mem_data),
        .out_rd_addr   (wb_rd_addr),
        .out_reg_write (wb_reg_write),
        .out_mem_to_reg(wb_mem_to_reg)
    );

    // ----------------------------------------------------------
    // INSTANCIA 9: Etapa WB (Write Back)
    // ----------------------------------------------------------
    WB_Stage u_wb (
        .alu_result (wb_alu_result),
        .mem_data   (wb_mem_data),
        .pc_plus4   (wb_pc_plus4),
        .mem_to_reg (wb_mem_to_reg),
        .write_data (wb_write_data)
    );

    // ----------------------------------------------------------
    // INSTANCIA 10: Unidad de detección de hazards
    // ----------------------------------------------------------
    Hazard_Unit u_hazard (
        .id_rs1_addr  (id_rs1_addr),
        .id_rs2_addr  (id_rs2_addr),
        .ex_rd_addr   (ex_rd_addr),
        .ex_mem_read  (ex_mem_read),
        .branch_taken (mem_branch_taken),
        .stall        (stall),
        .if_id_flush  (if_id_flush),
        .id_ex_flush  (id_ex_flush),
        .ex_mem_flush (ex_mem_flush)
    );

    // ----------------------------------------------------------
    // INSTANCIA 11: Unidad de forwarding
    // ----------------------------------------------------------
    Forwarding_Unit u_fwd (
        .ex_rs1_addr      (ex_rs1_addr),
        .ex_rs2_addr      (ex_rs2_addr),
        .mem_rd_addr      (mem_rd_addr),
        .mem_reg_write    (mem_reg_write),
        .wb_rd_addr       (wb_rd_addr),
        .wb_reg_write     (wb_reg_write),
        .fwd_a            (fwd_a),
        .fwd_b            (fwd_b)
    );

    // Salidas WB para síntesis en placa
    assign wb_result = wb_write_data;
    assign wb_rd     = wb_rd_addr;
    assign wb_we     = wb_reg_write;

    // ── Debug: contenido de latches ───────────────────────────
    // IF/ID
    assign dbg_ifid_pc    = id_pc;
    assign dbg_ifid_pc4   = id_pc_plus4;
    assign dbg_ifid_instr = id_instruction;
    // ID/EX — CTRL[31:27]=rd [26:22]=rs1a [21:17]=rs2a [16:13]=alu_op
    //          [12]=alu_src [11]=mem_rd [10]=mem_wr [9]=reg_wr
    //          [8]=mem2reg [7]=branch [6]=jump [5:0]=0
    assign dbg_idex_pc    = ex_pc;
    assign dbg_idex_rs1   = ex_rs1_data;
    assign dbg_idex_rs2   = ex_rs2_data;
    assign dbg_idex_imm   = ex_imm;
    assign dbg_idex_ctrl  = {ex_rd_addr, ex_rs1_addr, ex_rs2_addr,
                              ex_alu_op, ex_alu_src,
                              ex_mem_read, ex_mem_write, ex_reg_write,
                              ex_mem_to_reg, ex_branch, ex_jump, 6'b0};
    // EX/MEM — CTRL[31:27]=rd [26]=mem_rd [25]=mem_wr [24]=reg_wr
    //           [23]=mem2reg [22]=branch_taken [21:0]=0
    assign dbg_exmem_pc4  = mem_pc_plus4;
    assign dbg_exmem_alu  = mem_alu_result;
    assign dbg_exmem_rs2  = mem_rs2_data;
    assign dbg_exmem_btgt = mem_branch_target;
    assign dbg_exmem_ctrl = {mem_rd_addr, mem_mem_read, mem_mem_write,
                              mem_reg_write, mem_mem_to_reg,
                              mem_branch_taken, 22'b0};
    // MEM/WB — CTRL[31:27]=rd [26]=reg_wr [25]=mem2reg [24:0]=0
    assign dbg_memwb_pc4   = wb_pc_plus4;
    assign dbg_memwb_alu   = wb_alu_result;
    assign dbg_memwb_mdata = wb_mem_data;
    assign dbg_memwb_ctrl  = {wb_rd_addr, wb_reg_write, wb_mem_to_reg, 25'b0};

endmodule
