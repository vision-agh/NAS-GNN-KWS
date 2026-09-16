`timescale 1ns / 1ps

module hammard_ok #(
    parameter int DIM = 4,
    parameter int PRECISION = 8,
    parameter int MULTIPLIER = 0,
    parameter int ZERO_POINT_IN_1 = 0,
    parameter int ZERO_POINT_IN_2 = 0,
    parameter int ZERO_POINT_OUT = 0
)( 
    input  logic                        clk,
    input  logic                        reset,
    input  logic                        in_valid,
    input  logic signed [PRECISION:0]   vector_1 [DIM-1:0],
    input  logic signed [PRECISION:0]   vector_2 [DIM-1:0],
    output logic        [PRECISION-1:0] output_vector  [DIM-1:0],
    output logic                        out_valid
);
    logic signed [PRECISION:0]   input_reg_1 [DIM-1:0];
    logic signed [PRECISION:0]   input_reg_2 [DIM-1:0];
    logic signed [PRECISION:0]   val_1;
    logic signed [PRECISION:0]   val_2;
    logic signed [31:0]          vector_result;
    logic signed [63:0]          debug_mul;
    logic signed [63:0]          product;
    logic signed [PRECISION:0]   temp_sum;
    logic [PRECISION-1:0]        saturated_result;

    logic        state = 0;
    logic        state_reg = 0;
    logic        state_reg2 = 0;
    logic        state_reg3 = 0;
    logic        [$clog2(DIM) : 0] counter, counter_reg, counter_reg2, counter_reg3;

    initial begin
        output_vector <= '{default:0};
    end

    always @(posedge clk) begin
        if (reset) begin
            out_valid <= 0;
            state <= '0;
            counter <= '0;
            counter_reg <= '0;
        end
        else begin
            if (in_valid) begin
                state <= 1;
                counter <= '0;
                input_reg_1 <= vector_1;
                input_reg_2 <= vector_2;
            end
            if (state) begin
                counter <= counter + 1;
                if (counter == DIM-1) begin
                    state <= 0;
                end
            end
            out_valid <= '0;
            if (counter_reg3 == DIM-1) begin
                out_valid <= 1;
            end
            counter_reg <= counter;
            counter_reg2 <= counter_reg;
            counter_reg3 <= counter_reg2;
            state_reg <= state;
            state_reg2 <= state_reg;
            state_reg3 <= state_reg2;
        end
    end

    always @(posedge clk) begin
        val_1 <= input_reg_1[counter] - ((PRECISION+1)'(ZERO_POINT_IN_1));
        val_2 <= input_reg_2[counter] - ((PRECISION+1)'(ZERO_POINT_IN_2));
        vector_result <=  state_reg ? val_1 * val_2 : 32'sd0;
        product = (vector_result*MULTIPLIER);
        debug_mul = product>>>32;
        temp_sum <= debug_mul[PRECISION-1:0] + ZERO_POINT_OUT + product[31];

        if (temp_sum > $signed({1'b0, {PRECISION{1'b1}}})) begin
            saturated_result = {PRECISION{1'b1}};
        end else begin
            saturated_result = temp_sum[PRECISION-1:0];
        end
        output_vector[counter_reg3] <= state_reg3 ? saturated_result : '0;
    end

endmodule