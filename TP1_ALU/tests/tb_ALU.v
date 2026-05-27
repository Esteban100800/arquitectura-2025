`timescale 1ns/1ps

module tb_ALU;
    parameter NBDATA = 8;
    parameter NBOP = 6;

    reg [NBDATA-1:0] A, B;
    reg [NBOP-1:0] Op;
    wire [NBDATA-1:0] Result;
    wire Zero, Carry;

    // Instancia de la ALU
    ALU #(
        .NBDATA(NBDATA),
        .NBOP(NBOP)
    ) dut (
        .A(A),
        .B(B),
        .Op(Op),
        .Result(Result),
        .Zero(Zero),
        .Carry(Carry)
    );

    initial begin
        $display("A        B        Op      Result   Zero   Carry");
        // Suma
        A = 8'b00001010; B = 8'b00010100; Op = 6'b100000; #10;
        $display("%b %b %b %b %b %b", A, B, Op, Result, Zero, Carry);
        if (Result !== 8'b00011110) begin $display("ERROR en suma"); $stop; end
        // Resta
        A = 8'b00110010; B = 8'b00010100; Op = 6'b100010; #10;
        $display("%b %b %b %b %b %b", A, B, Op, Result, Zero, Carry);
        if (Result !== 8'b00011110) begin $display("ERROR en resta"); $stop; end
        // AND
        A = 8'b10101010; B = 8'b11001100; Op = 6'b100100; #10;
        $display("%b %b %b %b %b %b", A, B, Op, Result, Zero, Carry);
        if (Result !== (8'b10101010 & 8'b11001100)) begin $display("ERROR en AND"); $stop; end
        // OR
        A = 8'b10101010; B = 8'b11001100; Op = 6'b100101; #10;
        $display("%b %b %b %b %b %b", A, B, Op, Result, Zero, Carry);
        if (Result !== (8'b10101010 | 8'b11001100)) begin $display("ERROR en OR"); $stop; end
        // XOR
        A = 8'b10101010; B = 8'b11001100; Op = 6'b101000; #10;
        $display("%b %b %b %b %b %b", A, B, Op, Result, Zero, Carry);
        if (Result !== (8'b10101010 ^ 8'b11001100)) begin $display("ERROR en XOR"); $stop; end
        // Shift left
        A = 8'b00001111; B = 8'b0; Op = 6'b000010; #10;
        $display("%b %b %b %b %b %b", A, B, Op, Result, Zero, Carry);
        if (Result !== (8'b00001111 << 1)) begin $display("ERROR en shift left"); $stop; end
        // Shift right
        A = 8'b10000001; B = 8'b0; Op = 6'b000011; #10;
        $display("%b %b %b %b %b %b", A, B, Op, Result, Zero, Carry);
        if (Result !== (A >> 1)) begin $display("ERROR en shift right"); $stop; end
        // NOR
        A = 8'b11110000; B = 8'b00001111; Op = 6'b100111; #10;
        $display("%b %b %b %b %b %b", A, B, Op, Result, Zero, Carry);
        if (Result !== ~(8'b11110000 | 8'b00001111)) begin $display("ERROR en NOR"); $stop; end
        // Default
        A = 8'b00000000; B = 8'b00000000; Op = 6'b000000; #10;
        $display("%b %b %b %b %b %b", A, B, Op, Result, Zero, Carry);
        if (Result !== 8'b00000000) begin $display("ERROR en default"); $stop; end
        // Test de Carry (suma que desborda)
        A = 8'b11111111; B = 8'b01100100; Op = 6'b100000; #10;
        $display("Carry test: %b + %b = %b, Carry = %b", A, B, Result, Carry);
        if (Carry !== 1'b1) begin $display("ERROR en Carry (suma)"); $stop; end
        // Test de Zero (resultado cero)
        A = 8'b00110010; B = -8'b00110010; Op = 6'b100000; #10;
        $display("Zero test: %b + %b = %b, Zero = %b", A, B, Result, Zero);
        if (Zero !== 1'b1) begin $display("ERROR en Zero (suma)"); $stop; end
        $display("TESTBENCH FINALIZADO CORRECTAMENTE");
        $finish;
    end
endmodule