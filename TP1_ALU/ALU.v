module ALU #(
    parameter NBDATA = 8,
    parameter NBOP = 6
) (
    input [NBDATA-1:0] A,
    input [NBDATA-1:0] B,
    input [NBOP-1:0] Op,
    output reg [NBDATA-1:0] Result,
    output reg Zero,
    output reg Carry
);
    reg [NBDATA:0] result_tmp;

always @(*) begin
    Carry = 1'b0;
    case (Op)
        6'b100000: begin // Suma
            result_tmp = A + B;
            Carry = result_tmp[NBDATA];
        end
        6'b100010: begin // Resta
            result_tmp = A - B;
            Carry = result_tmp[NBDATA];
        end
        6'b100100: result_tmp = A & B;
        6'b100101: result_tmp = A | B;
        6'b101000: result_tmp = A ^ B;
        6'b000010: result_tmp = A << 1;
        6'b000011: result_tmp = A >> 1;
        6'b100111: result_tmp = ~(A | B);
        default: result_tmp = 0;
    endcase
    Result = result_tmp[NBDATA-1:0];
    Zero = (Result == {NBDATA{1'b0}});
end
endmodule