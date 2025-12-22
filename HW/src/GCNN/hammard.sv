module hammard #(
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
    logic signed [31:0]         vector_result;
    logic signed [63:0]         debug_mul;
    logic signed [63:0]         product;
    logic signed [PRECISION:0]  temp_sum;
    logic [PRECISION-1:0]       saturated_result;

    logic        state = 0;
    logic        state_reg = 0;
    logic        [$clog2(DIM) : 0] counter;
    logic        [$clog2(DIM) : 0] counter_reg;

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
            if (counter_reg == DIM-1) begin
                out_valid <= 1;
            end
            counter_reg <= counter;
            state_reg <= state;
        end
    end

    always @(posedge clk) begin
        vector_result <=  state ? (input_reg_1[counter] - ZERO_POINT_IN_1) * (input_reg_2[counter] - ZERO_POINT_IN_2) : '0;
        product = (vector_result*MULTIPLIER);
        debug_mul = product>>>32;
        temp_sum = debug_mul[PRECISION-1:0] + ZERO_POINT_OUT + product[31];

        if (temp_sum > $signed({1'b0, {PRECISION{1'b1}}})) begin
            saturated_result = {PRECISION{1'b1}};
        end else begin
            saturated_result = temp_sum[PRECISION-1:0];
        end
        output_vector[counter_reg] <= state_reg ? saturated_result : '0;
    end

endmodule