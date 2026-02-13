`timescale 1ns / 1ps

import nas_pkg::*;

module maxpool #(
    parameter int OUTPUT_DIM = OUTPUT_DIM_4,
    parameter int TIME_WINDOW = 10000000,
    parameter int PRECISION = PRECISION_CONV4,
    parameter int ZERO_POINT = 136
)(
    input  logic                  clk,
    input  logic                  reset,
    input event_type              in_event,
    input  logic [T_WIDTH-1 : 0]  last_time,
    input  logic  [PRECISION-1:0] in_features [OUTPUT_DIM-1:0],
    output logic [PRECISION-1 :0] out_features [OUTPUT_DIM-1 : 0],
    output logic                  out_valid
);
    logic [63:0]   threshold = TIME_WINDOW;
    logic          reset_max;
    logic          valid_reg; 
    logic [T_WIDTH-1 : 0]  time_now = 0;

    genvar i;
    generate
        for (i = 0; i < OUTPUT_DIM; i++) begin : calc_max
            always @(posedge clk) begin
                if (reset) begin
                    out_features[i] <= ZERO_POINT;
                end
                else begin
                    if (in_event.valid) begin
                        out_features[i] <= (in_features[i] > out_features[i]) ? in_features[i] : out_features[i];
                        time_now <= in_event.t;
                    end
                    if (reset_max) begin
                        out_features[i] <= ZERO_POINT;
                    end
                    out_valid <= reset_max;
                    valid_reg <= in_event.valid;
                end
            end
        end
    endgenerate

    assign reset_max = (last_time == time_now) && valid_reg;

endmodule
