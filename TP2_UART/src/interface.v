module interface (
    input  wire       i_clk,
    input  wire       i_reset,
    // TX
    input  wire [7:0] input_alu_data,
    output reg  [7:0] data_in,
    input  wire       tx_done,
    output reg        tx_full,
    input  wire       wr,
    output reg        tx_start,
    // RX
    input  wire       rd,
    output reg  [7:0] rx_data,
    input  wire [7:0] data_in_rx,
    input  wire       rx_done,
    output reg        rx_empty
);
    // tx maquina de estados de dos estados 
    
    localparam TX_IDLE = 1'b0;
    localparam TX_WAIT = 1'b1;

    reg state_tx;

    always @(posedge i_clk) begin
        if (i_reset) begin
            state_tx <= TX_IDLE;
            tx_start <= 0;
            tx_full  <= 0;
            data_in  <= 0;
        end else begin
            tx_start <= 0; // por defecto: no transmitir

            case (state_tx)
                TX_IDLE: begin
                    tx_full <= 0;
                    if (wr) begin
                        data_in  <= input_alu_data;
                        tx_start <= 1;
                        tx_full  <= 1;
                        state_tx <= TX_WAIT;
                    end
                end
                TX_WAIT: begin
                    tx_full <= 1;
                    if (tx_done) begin
                        tx_full  <= 0;
                        state_tx <= TX_IDLE;
                    end
                end
                default: state_tx <= TX_IDLE;
            endcase
        end
    end

    //push en rx done, pop con rd, fifo de 8 bytes
    reg [7:0] fifo     [0:7];
    reg [2:0] wr_ptr;
    reg [2:0] rd_ptr;
    reg [3:0] count;

    // deteccion de flanco para no hacer pop multiples veces
    reg rd_prev;
    wire rd_pulse = rd && !rd_prev;

    wire push = rx_done  && (count < 4'd8);
    wire pop  = rd_pulse && (count > 4'd0);

    always @(posedge i_clk) begin
        if (i_reset) begin
            wr_ptr   <= 0;
            rd_ptr   <= 0;
            count    <= 0;
            rx_empty <= 1;
            rx_data  <= 0;
            rd_prev  <= 0;
        end else begin
            rd_prev <= rd;

            if (push) begin
                fifo[wr_ptr] <= data_in_rx;
                wr_ptr       <= wr_ptr + 1;
            end

            if (pop) begin
                rx_data <= fifo[rd_ptr];
                rd_ptr  <= rd_ptr + 1;
            end

            case ({push, pop})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
                default: ; // 00 o 11: sin cambio neto
            endcase

            rx_empty <= (count == 0) || (pop && !push && count == 1);
        end
    end

endmodule
