module top_system (
    input  wire       i_clk,
    input  wire       i_reset,
    input  wire [7:0] i_sw,
    input  wire [2:0] i_btn,
    input  wire       i_wr_send,
    output wire       tx,
    input  wire       rx,
    input  wire       rd,
    output wire [7:0] o_led,    // muestra el ultimo byte recibido por UART
    output wire       o_carry,
    output wire       o_zero
);
    wire [7:0] alu_data_out;
    wire [7:0] interface_data_in;
    wire tx_start, tx_done, tx_full;
    wire data_ready;
    wire [7:0] uart_data_out;
    wire [7:0] rx_data;

    // deteccion de flanco para wr: envia solo cuando el switch sube
    reg wr_prev;
    wire wr;
    assign wr = i_wr_send && !wr_prev;

    always @(posedge i_clk) begin
        if (i_reset) wr_prev <= 0;
        else         wr_prev <= i_wr_send;
    end

    alu_top alu_inst (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_sw(i_sw),
        .i_btn(i_btn),
        .o_Result(alu_data_out),
        .o_Zero(o_zero),
        .o_Carry(o_carry)
    );

    interface interface_inst (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .input_alu_data(alu_data_out),
        .data_in(interface_data_in),
        .tx_done(tx_done),
        .tx_full(tx_full),
        .wr(wr),
        .tx_start(tx_start),
        .rd(rd),
        .rx_data(rx_data),
        .data_in_rx(uart_data_out),
        .rx_done(data_ready),
        .rx_empty()
    );

    UART uart_inst (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .rx(rx),
        .tx(tx),
        .data_in(interface_data_in),
        .data_out(uart_data_out),
        .data_ready(data_ready),
        .tx_start(tx_start),
        .tx_done(tx_done)
    );

    // el ultimo byte recibido se muestra en los LEDs
    assign o_led = rx_data;

endmodule
