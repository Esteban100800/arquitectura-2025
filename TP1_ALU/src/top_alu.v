`timescale 1ns / 1ps

module top_alu (
    input wire [7:0] i_sw,
    input wire [2:0] i_btn,
    input wire i_clk,
    input wire i_reset,
    output wire [7:0] o_Result,
    output wire o_Zero,
    output wire o_Carry
);

    reg [7:0] i_A_reg;
    reg [7:0] i_B_reg;
    reg [5:0] i_opcode_reg;

    alu  #(
        .NBDATA(8),
        .NBOP(6)
    ) alu_inst (
        .A(i_A_reg),
        .B(i_B_reg),
        .Op(i_opcode_reg),
        .Result(o_Result),
        .Zero(o_Zero),
        .Carry(o_Carry)
    );

    always @(posedge i_clk) begin
        if (i_reset) begin
            i_A_reg <= 0;
            i_B_reg <= 0;
            i_opcode_reg <= 0;
        end else begin
            if (i_btn[0]) i_A_reg <= i_sw;
            if (i_btn[1]) i_B_reg <= i_sw;
            if (i_btn[2]) i_opcode_reg <= i_sw [5:0];
        end    
    end
endmodule