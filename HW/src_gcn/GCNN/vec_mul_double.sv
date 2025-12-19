`timescale 1ns / 1ps

module vec_mul_double #(
    parameter int PRECISION_F = 8,
    parameter int PRECISION_W = 8
)( 
    input  logic                   clk,
    input  logic                   en,
    input  logic [PRECISION_F-1:0] features[1:0],
    input  logic [PRECISION_W-1:0] weights[1:0],
    output logic [31:0]            sum, 
    output logic [31:0]            result 
);

    logic [31:0] result_reg [1:0];
    logic [31:0] sum_reg;

    always @(posedge clk) begin
        result_reg[0] <= en ? (features[0] * weights[0]) : result_reg[0];
        result_reg[1] <= en ? (features[1] * weights[1]) : result_reg[1];
        sum_reg <= features[0] + features[1];

        sum <= sum_reg;
        result <= result_reg[0] + result_reg[1];
    end

endmodule

