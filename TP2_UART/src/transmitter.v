module transmitter #(
    parameter BAUD_RATE = 9600
)(
    input  wire       i_clk,
    input  wire       i_reset,
    output reg        tx,
    input  wire       baud_tick,
    input  wire       tx_start,
    input  wire [7:0] data_in,
    output reg        tx_done
);
    localparam IDLE      = 2'd0;
    localparam START     = 2'd1;
    localparam SEND_DATA = 2'd2;
    localparam STOP_BIT  = 2'd3;

    reg [1:0] state;
    reg [3:0] tick_counter;
    reg [2:0] bit_index;
    reg [7:0] data_latch;

    always @(posedge i_clk) begin
        if (i_reset) begin
            state        <= IDLE;
            tx           <= 1'b1;
            tx_done      <= 1'b0;
            tick_counter <= 0;
            bit_index    <= 0;
            data_latch   <= 0;
        end else begin
            tx_done <= 0; // pulso de un ciclo por defecto

            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    if (tx_start) begin
                        data_latch   <= data_in;
                        tick_counter <= 0;
                        state        <= START;
                    end
                end

                START: begin
                    tx <= 1'b0; // start bit
                    if (baud_tick) begin
                        if (tick_counter == 4'd15) begin
                            tick_counter <= 0;
                            bit_index    <= 0;
                            state        <= SEND_DATA;
                        end else begin
                            tick_counter <= tick_counter + 1;
                        end
                    end
                end

                SEND_DATA: begin
                    tx <= data_latch[bit_index];
                    if (baud_tick) begin
                        if (tick_counter == 4'd15) begin
                            tick_counter <= 0;
                            if (bit_index == 3'd7)
                                state <= STOP_BIT;
                            else
                                bit_index <= bit_index + 1;
                        end else begin
                            tick_counter <= tick_counter + 1;
                        end
                    end
                end

                STOP_BIT: begin
                    tx <= 1'b1; // stop bit
                    if (baud_tick) begin
                        if (tick_counter == 4'd15) begin
                            tx_done      <= 1'b1;
                            tick_counter <= 0;
                            state        <= IDLE;
                        end else begin
                            tick_counter <= tick_counter + 1;
                        end
                    end
                end

                default: begin
                    tx    <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
