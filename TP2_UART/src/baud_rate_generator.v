module baud_rate_generator #(
    parameter CLOCK_FREQ = 100000000,
    parameter BAUD_RATE  = 9600
)(
    input  wire clk,
    input  wire reset,
    output reg  baud_tick
);
    localparam integer DIVISOR = CLOCK_FREQ / (BAUD_RATE * 16);

    reg [15:0] counter;

    always @(posedge clk) begin
        if (reset) begin
            counter   <= 0;
            baud_tick <= 0;
        end else if (counter == DIVISOR - 1) begin
            counter   <= 0;
            baud_tick <= 1;
        end else begin
            counter   <= counter + 1;
            baud_tick <= 0;
        end
    end
endmodule
