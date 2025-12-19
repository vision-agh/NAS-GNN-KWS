`timescale 1ns / 1ps

module vec_mul_nine #(
    parameter int PRECISION_F = 8,
    parameter int PRECISION_W = 8
)( 
    input  logic                   clk,
    input  logic                   en,
    input  logic [PRECISION_F-1:0] features [8:0],
    input  logic [PRECISION_W-1:0] weights  [8:0],
    output logic [31:0]            sum, 
    output logic [31:0]            result 
);

    logic [31:0] result_reg [8:0];
    logic [31:0] sum_reg;

    genvar j;
    generate
        always @(posedge clk) begin
            for (int j=0; j<9; j=j+1) begin: multiply
                result_reg[j] <= en ? (features[j] * weights[j]) : result_reg[j];
            end
            sum_reg <= en ? features[0] + 
                      features[1] + 
                      features[2] + 
                      features[3] + 
                      features[4] +
                      features[5] + 
                      features[6] + 
                      features[7] + 
                      features[8] : sum_reg;

            sum <= sum_reg;
            result <= result_reg[0] + 
                      result_reg[1] + 
                      result_reg[2] + 
                      result_reg[3] + 
                      result_reg[4] +
                      result_reg[5] + 
                      result_reg[6] + 
                      result_reg[7] + 
                      result_reg[8];
        end
    endgenerate

endmodule

