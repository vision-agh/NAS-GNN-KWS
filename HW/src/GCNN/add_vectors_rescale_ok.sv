`timescale 1ns / 1ps

module add_vectors_rescale_ok #(
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

    logic signed [63:0] product_one;
    logic signed [63:0] product_two;
    logic signed [63:0] product_one_reg;
    logic signed [63:0] product_two_reg;
    logic signed [63:0] product_sum;
    logic signed [63:0] shifted_sum;
    logic signed [PRECISION:0]   input_reg_1 [DIM-1:0];
    logic signed [PRECISION:0]   input_reg_2 [DIM-1:0];
    logic signed [PRECISION:0] temp_sum;
    logic        [PRECISION-1:0] saturated_result;
    logic        state = 0;
    logic        state_reg = 0;
    logic        state_reg2 = 0;
    logic        state_reg3 = 0;

    logic        [$clog2(DIM) : 0] counter;
    logic        [$clog2(DIM) : 0] counter_reg, counter_reg2, counter_reg3, counter_reg4, counter_reg5;

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
            if (counter_reg5 == DIM-1) begin
                out_valid <= 1;
            end
            counter_reg <= counter;
            counter_reg2 <= counter_reg;
            counter_reg3 <= counter_reg2;
            counter_reg4 <= counter_reg3;
            counter_reg5 <= counter_reg4;
            state_reg <= state;
            state_reg2 <= state_reg;
            state_reg3 <= state_reg2;
        end
    end

    assign shifted_sum = product_sum >>> 32;

    always @(posedge clk) begin
        // Stage 1: register the two constant multiplies on their own -
        // nothing else shares this cycle with them.
        product_one <= $signed(input_reg_1[counter] - ZERO_POINT_IN_1);
        product_two <= $signed(input_reg_2[counter] - ZERO_POINT_IN_2);
        
        product_one_reg <= $signed(product_one) * $signed(MULTIPLIER_IN_1);
        product_two_reg <= $signed(product_two) * $signed(MULTIPLIER_IN_2);

        // Stage 2: the 64-bit add now gets a full cycle to itself instead of
        // being chained straight after the multiplies (that chain was the
        // critical path).
        product_sum <= state_reg2 ? (product_one_reg + product_two_reg) : '0;

        // Stage 3: >>>32 and the bit-31 rounding term are pure wiring (free),
        // so folding them in here costs nothing - same math as before,
        // just rescheduled.
        temp_sum <= state_reg3 ? (shifted_sum[PRECISION-1:0] + ZERO_POINT_OUT) + product_sum[31] : '0;

        // Stage 4: saturate.
        if (temp_sum > $signed({1'b0, {PRECISION{1'b1}}})) begin
            saturated_result <= {PRECISION{1'b1}};
        end else begin
            saturated_result <= temp_sum[PRECISION-1:0];
        end

        // Stage 5: commit.
        output_vector[counter_reg5] <= saturated_result;
    end

endmodule