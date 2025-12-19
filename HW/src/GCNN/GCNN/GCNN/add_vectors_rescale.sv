`timescale 1ns / 1ps

module add_vectors_rescale #(
    parameter int DIM = 4,
    parameter int PRECISION = 8,
    parameter longint MULTIPLIER_IN_1 = 0,
    parameter longint MULTIPLIER_IN_2 = 0,
    parameter int ZERO_POINT_IN_1 = 0,
    parameter int ZERO_POINT_IN_2 = 0,
    parameter int ZERO_POINT_OUT = 0
)( 
    input  logic                        clk,
    input  logic                        reset,
    input  logic                        in_valid,
    input  logic signed [PRECISION:0]   input_vector_1 [DIM-1:0],
    input  logic signed [PRECISION:0]   input_vector_2 [DIM-1:0],
    output logic        [PRECISION-1:0] output_vector   [DIM-1:0],
    output logic                        out_valid
);

    initial begin
        output_vector <= '{default:0};
    end

    logic signed [63:0] product;
    logic               product_reg;
    logic signed [PRECISION:0]   input_reg_1 [DIM-1:0];
    logic signed [PRECISION:0]   input_reg_2 [DIM-1:0];
    logic signed [63:0] debug_mul;
    logic signed [PRECISION:0] temp_sum;
    logic        [PRECISION-1:0] saturated_result;
    logic        state = 0;
    logic        state_reg = 0;
    logic        state_reg2 = 0;

    logic        [$clog2(DIM) : 0] counter;
    logic        [$clog2(DIM) : 0] counter_reg, counter_reg2, counter_reg3, counter_reg4;

    always @(posedge clk) begin
        if (reset) begin
            out_valid <= 0;
            state <= '0;
            counter_reg <= '0;
            counter_reg2 <= '0;
        end
        else begin
            if (in_valid) begin
                state <= 1;
                counter <= '0;
                input_reg_1 <= input_vector_1;
                input_reg_2 <= input_vector_2;
            end
            if (state) begin
                counter <= counter + 1;
                if (counter == DIM-1) begin
                    state <= 0;
                end
            end
            out_valid <= '0;
            if (counter_reg4 == DIM-1) begin
                out_valid <= 1;
            end
            counter_reg <= counter;
            counter_reg2 <= counter_reg;
            counter_reg3 <= counter_reg2;
            counter_reg4 <= counter_reg3;
            state_reg <= state;
            state_reg2 <= state_reg;
        end
    end

    always @(posedge clk) begin
        product <=  state ? $signed(input_reg_1[counter] - ZERO_POINT_IN_1) * $signed(MULTIPLIER_IN_1) +
                        $signed(input_reg_2[counter] - ZERO_POINT_IN_2) * $signed(MULTIPLIER_IN_2) : '0;
        product_reg <= product[31];
        debug_mul <= state_reg ? (product) >>> 32 : '0;
        temp_sum <= state_reg2 ? (debug_mul[PRECISION-1:0] + ZERO_POINT_OUT) + product_reg: '0;
        if (temp_sum > $signed({1'b0, {PRECISION{1'b1}}})) begin
            saturated_result <= {PRECISION{1'b1}};
        end else begin
            saturated_result <= temp_sum[PRECISION-1:0];
        end
        output_vector[counter_reg4] <= saturated_result;
    end

endmodule