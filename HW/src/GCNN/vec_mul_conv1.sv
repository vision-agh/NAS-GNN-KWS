`timescale 1ns / 1ps

module vec_mul_conv1 #(
    parameter int INPUT_DIM = 4,
    parameter int PRECISION_IN = 8,
    parameter int PRECISION_OUT = 8
)( 
    input  logic                     clk,
    input  logic                     en,
    input  logic [PRECISION_IN-1:0]  feature_vector [INPUT_DIM-1:0],
    input  logic [PRECISION_OUT-1:0] weight_vector  [INPUT_DIM-1:0],
    input  logic signed [31:0]       bias,
    input  logic                     relu,
    input  logic [31:0]              multiplier,
    input  logic [PRECISION_OUT-1:0] zero_point_weight,
    input  logic [PRECISION_OUT-1:0] zero_point_out,
    output logic [PRECISION_OUT-1:0] result
);
    
    logic [31:0] results_reg;
    logic [31:0] sums_reg, sums_reg2;
    logic [31:0] result_reg;
    logic [31:0] sum_reg;
    logic signed [31:0] result_with_bias;
    logic signed [31:0] result_with_sum;
    logic signed [63:0] result_scaled;

    logic                     relu_delayed;
    logic signed [31:0]       bias_delayed;
    logic [31:0]              multiplier_delayed;
    logic [PRECISION_OUT-1:0] zero_point_weight_delayed;
    logic [PRECISION_OUT-1:0] zero_point_out_delayed;

    vec_mul_five #(
        .PRECISION_F  ( PRECISION_IN  ),
        .PRECISION_W  ( PRECISION_OUT )
    ) u_word_mul (
        .clk       ( clk            ),
        .en        ( en             ),
        .features  ( feature_vector ),
        .weights   ( weight_vector  ),
        .sum       ( sums_reg       ),
        .result    ( results_reg    )
    );

    always @(posedge clk) begin
        result_reg <= results_reg;
        sums_reg2 <= sums_reg;
        sum_reg <= sums_reg2;
    end

    delay_module #(
        .N        ( 32  ),
        .DELAY    ( 3   )
    ) delay_bias (
        .clk   ( clk          ),
        .idata ( bias         ),
        .odata ( bias_delayed )
    );

    delay_module #(
        .N        ( PRECISION_OUT  ),
        .DELAY    ( 4              )
    ) delay_zero_point_wright (
        .clk   ( clk                       ),
        .idata ( zero_point_weight         ),
        .odata ( zero_point_weight_delayed )
    );

    delay_module #(
        .N        ( 32  ),
        .DELAY    ( 5   )
    ) delay_multipler (
        .clk   ( clk                ),
        .idata ( multiplier         ),
        .odata ( multiplier_delayed )
    );

    delay_module #(
        .N        ( PRECISION_OUT  ),
        .DELAY    ( 6              )
    ) delay_zero_point_out (
        .clk   ( clk                    ),
        .idata ( zero_point_out         ),
        .odata ( zero_point_out_delayed )
    );


    delay_module #(
        .N        ( 1  ),
        .DELAY    ( 6  )
    ) delay_relu (
        .clk   ( clk          ),
        .idata ( relu         ),
        .odata ( relu_delayed )
    );

    always @(posedge clk) begin
        result_with_bias <= $signed(result_reg) + bias_delayed;
        result_with_sum <= result_with_bias - (sum_reg*zero_point_weight_delayed);
        result_scaled <= result_with_sum*$signed(multiplier_delayed);
        result <= (relu_delayed && result_scaled < 0) ? zero_point_out_delayed :
                                                        (result_scaled>>>32) + result_scaled[31] + zero_point_out_delayed;
    end

endmodule

