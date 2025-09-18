module ALU #(
    parameter NBDATA = 8,
    parameter NBOP = 6
) (
    input signed [NBDATA-1:0] A,
    input signed [NBDATA-1:0] B,
    input [NBOP-1:0] Op,
    output reg signed [NBDATA-1:0] Result,
    output reg Zero,
    output reg Carry
);
always @(*) begin
    case (Op)
        6'b100000: Result = A + B;
        6'b100010: Result = A - B;
        6'b100100: Result = A & B;
        6'b100101: Result = A | B;
        6'b101000: Result = A ^ B;
        6'b000010: Result = A <<< 1;
        6'b000011: Result = A >>> 1;
        6'b100111: Result = ~(A | B);
        default: Result = 6'b000000;
    endcase
    Zero = (Result == 6'b000000);
    Carry = (Result > 6'b111111) ? 1 : 0;

end
endmodule