`timescale 1ns / 1ps

module vector_multiplication_dsp #(
    parameter int INPUT_DIM = 4,
    parameter int PRECISION_IN = 8,
    parameter int PRECISION_OUT = 8,
    parameter int MULTIPLIER = 0,
    parameter int ZERO_POINT = 0
)( 
    input  logic                            clk,
    input  logic                            reset,
    input  logic signed [PRECISION_IN:0]    feature_matrix [INPUT_DIM-1:0],
    input  logic signed [PRECISION_OUT:0]   weight_matrix  [INPUT_DIM-1:0],
    input  logic signed [31:0]              bias,
    output logic        [PRECISION_OUT-1:0] output_matrix  
);

    localparam PARALLEL = INPUT_DIM / 4;

    logic signed [24:0]           matrix_result [INPUT_DIM-1 : 0];
    logic signed [63:0]           debug_bias ;
    logic signed [63:0]           debug_mul;
    logic signed [31:0]           bias_reg;

    genvar p;
    generate
        for (p = 0; p < INPUT_DIM; p++) begin : multiply
            mult_gen_0 multi (
                .CLK (clk),
                .A   ( feature_matrix[p] ),
                .B   ( weight_matrix[p]  ),
                .P   ( matrix_result[p]  )
            );
        end
    endgenerate

    always @(posedge clk) begin
        debug_bias = bias_reg;
        for (int i=0; i< INPUT_DIM; i++) begin
            debug_bias = debug_bias + matrix_result[i];
        end
        debug_mul <= debug_bias;
        output_matrix <= ((debug_mul*MULTIPLIER)>>>32) + ZERO_POINT;
        bias_reg <= bias;
    end

endmodule


