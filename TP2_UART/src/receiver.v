module receiver #(
    parameter BAUD_RATE = 9600
)(
    input  wire       i_clk,
    input  wire       i_reset,
    input  wire       rx,
    input  wire       baud_tick,
    output reg  [7:0] data_out,
    output reg        data_ready
);
    localparam WAIT_START    = 2'd0;
    localparam RECEIVE_DATA  = 2'd1;
    localparam STOP_BIT      = 2'd2;

    reg [1:0] state;
    reg [3:0] tick_counter;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;

    always @(posedge i_clk) begin
        if (i_reset) begin
            state        <= WAIT_START;
            tick_counter <= 0;
            bit_index    <= 0;
            shift_reg    <= 0;
            data_out     <= 0;
            data_ready   <= 0;
        end else begin
            data_ready <= 0; // pulso de un ciclo por defecto

            case (state)
                WAIT_START: begin
                    if (baud_tick) begin
                        if (rx == 1'b0) begin
                            if (tick_counter == 4'd7) begin
                                // mitad del start bit confirmado
                                tick_counter <= 0;
                                bit_index    <= 0;
                                state        <= RECEIVE_DATA;
                            end else begin
                                tick_counter <= tick_counter + 1;
                            end
                        end else begin
                            tick_counter <= 0; // rx volvio a 1, era ruido
                        end
                    end
                end

                RECEIVE_DATA: begin
                    if (baud_tick) begin
                        if (tick_counter == 4'd15) begin
                            // muestreo en la mitad de cada bit
                            shift_reg[bit_index] <= rx;
                            tick_counter         <= 0;
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
                    if (baud_tick) begin
                        if (tick_counter == 4'd15) begin
                            data_out     <= shift_reg;
                            data_ready   <= 1'b1;
                            tick_counter <= 0;
                            state        <= WAIT_START;
                        end else begin
                            tick_counter <= tick_counter + 1;
                        end
                    end
                end

                default: state <= WAIT_START;
            endcase
        end
    end
endmodule
