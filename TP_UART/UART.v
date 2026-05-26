module UART #(
    parameter CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE  = 9600
)(
    input  wire       i_clk,
    input  wire       i_reset,
    input  wire       rx,
    output wire       tx,
    input  wire [7:0] data_in,
    output wire [7:0] data_out,
    output wire       data_ready,
    input  wire       tx_start,
    output wire       tx_done
);
    wire baud_tick;

    baud_rate_generator #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) baud_gen_inst (
        .clk(i_clk),
        .reset(i_reset),
        .baud_tick(baud_tick)
    );

    receiver #(
        .BAUD_RATE(BAUD_RATE)
    ) rx_inst (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .rx(rx),
        .baud_tick(baud_tick),
        .data_out(data_out),
        .data_ready(data_ready)
    );

    transmitter #(
        .BAUD_RATE(BAUD_RATE)
    ) tx_inst (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .tx(tx),
        .baud_tick(baud_tick),
        .data_in(data_in),
        .tx_start(tx_start),
        .tx_done(tx_done)
    );

endmodule
