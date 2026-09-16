`timescale 1ns / 1ps

module vec_mul_ok #(
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
    
    localparam IS_OFFSET = (INPUT_DIM % 6 == 0) ? 0 : 1;
    localparam PARALLEL = (INPUT_DIM - (2*IS_OFFSET)) / 6;
    localparam int NUM_TERMS  = PARALLEL + 1;
    localparam int HALF_TERMS = NUM_TERMS/2;
    logic [31:0] results_reg [PARALLEL:0];
    logic [31:0] sums_reg [PARALLEL:0];
    logic [31:0] results_reg2 [PARALLEL:0];
    logic [31:0] sums_reg2 [PARALLEL:0];
    logic [31:0] results_reg3 [PARALLEL:0];
    logic [31:0] sums_reg3 [PARALLEL:0];
    logic [31:0] result_reg_accumulate_lo, result_reg_accumulate_hi;
    logic [31:0] sum_reg_accumulate_lo, sum_reg_accumulate_hi;
    logic [31:0] result_partial_lo_reg;
    logic [31:0] sum_partial_lo_reg;
    logic [31:0] result_reg;
    logic [31:0] sum_reg, sum_reg2;
    logic signed [31:0] result_with_bias;
    logic signed [31:0] result_with_sum;
    logic signed [63:0] result_scaled;

    logic                     relu_delayed;
    logic signed [31:0]       bias_delayed;
    logic [31:0]              multiplier_delayed;
    logic [PRECISION_OUT-1:0] zero_point_weight_delayed;
    logic [PRECISION_OUT-1:0] zero_point_out_delayed;

    genvar p;
    generate
        for (p = 0; p < PARALLEL; p++) begin : multiply
            vec_mul_six_ok #(
                .PRECISION_F     ( PRECISION_IN   ),
                .PRECISION_W     ( PRECISION_OUT  )
            ) u_word_mul (
                .clk       ( clk                               ),
                .en        ( en                                ),
                .features  ( feature_vector[(6*(p+1))-1:(6*p)] ),
                .weights   ( weight_vector[(6*(p+1))-1:(6*p)]  ),
                .sum       ( sums_reg[p]                       ),
                .result    ( results_reg[p]                    )
            );
        end
        if ( IS_OFFSET ) begin
            vec_mul_double_ok #(
                .PRECISION_F     ( PRECISION_IN   ),
                .PRECISION_W     ( PRECISION_OUT  )
            ) u_word_mul_last (
                .clk       ( clk                                     ),
                .en        ( en                                      ),
                .features  ( feature_vector[INPUT_DIM-1:INPUT_DIM-2] ),
                .weights   ( weight_vector[INPUT_DIM-1:INPUT_DIM-2]  ),
                .sum       ( sums_reg[PARALLEL]                      ),
                .result    ( results_reg[PARALLEL]                   )
            );
        end
        else begin
            assign results_reg[PARALLEL] = '0;
            assign sums_reg[PARALLEL] = '0;
        end
    endgenerate

    always @(posedge clk) begin
        result_reg_accumulate_lo = 0;
        result_reg_accumulate_hi = 0;
        sum_reg_accumulate_lo = 0;
        sum_reg_accumulate_hi = 0;

        // lower half: summed from reg2 (registered below, aligned with reg3)
        for (int j = 0; j < HALF_TERMS; j = j+1) begin: accumulate_lo
            result_reg_accumulate_lo = result_reg_accumulate_lo + results_reg2[j];
            sum_reg_accumulate_lo    = sum_reg_accumulate_lo    + sums_reg2[j];
        end
        // upper half: summed from reg3, combined with the already-registered lower half
        for (int j = HALF_TERMS; j <= PARALLEL; j = j+1) begin: accumulate_hi
            result_reg_accumulate_hi = result_reg_accumulate_hi + results_reg3[j];
            sum_reg_accumulate_hi    = sum_reg_accumulate_hi    + sums_reg3[j];
        end

        for (int j=0; j <= PARALLEL; j=j+1) begin: shift
            results_reg2[j] <= results_reg[j];
            results_reg3[j] <= results_reg2[j];
            sums_reg2[j] <= sums_reg[j];
            sums_reg3[j] <= sums_reg2[j];
        end

        result_partial_lo_reg <= result_reg_accumulate_lo;
        sum_partial_lo_reg    <= sum_reg_accumulate_lo;

        result_reg <= result_partial_lo_reg + result_reg_accumulate_hi;
        sum_reg     <= sum_partial_lo_reg    + sum_reg_accumulate_hi;
        sum_reg2    <= sum_reg;
    end

    delay_module #(
        .N        ( 32  ),
        .DELAY    ( 6   )
    ) delay_bias (
        .clk   ( clk          ),
        .idata ( bias         ),
        .odata ( bias_delayed )
    );

    delay_module #(
        .N        ( PRECISION_OUT  ),
        .DELAY    ( 7              )
    ) delay_zero_point_wright (
        .clk   ( clk                       ),
        .idata ( zero_point_weight         ),
        .odata ( zero_point_weight_delayed )
    );

    delay_module #(
        .N        ( 32  ),
        .DELAY    ( 8   )
    ) delay_multipler (
        .clk   ( clk                ),
        .idata ( multiplier         ),
        .odata ( multiplier_delayed )
    );

    delay_module #(
        .N        ( PRECISION_OUT  ),
        .DELAY    ( 9              )
    ) delay_zero_point_out (
        .clk   ( clk                    ),
        .idata ( zero_point_out         ),
        .odata ( zero_point_out_delayed )
    );


    delay_module #(
        .N        ( 1  ),
        .DELAY    ( 9  )
    ) delay_relu (
        .clk   ( clk          ),
        .idata ( relu         ),
        .odata ( relu_delayed )
    );

    always @(posedge clk) begin
        result_with_bias <= $signed(result_reg) + bias_delayed;
        result_with_sum <= result_with_bias - (sum_reg2*zero_point_weight_delayed);
        result_scaled <= result_with_sum*$signed(multiplier_delayed);
        result <= (relu_delayed && result_scaled < 0) ? zero_point_out_delayed :
                                                        (result_scaled>>>32) + result_scaled[31] + zero_point_out_delayed;
    end

endmodule

