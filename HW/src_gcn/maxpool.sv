`timescale 1ns / 1ps

import graph_pkg::*;

module maxpool #(
    parameter int OUTPUT_DIM = OUTPUT_DIM_4,
    parameter int TIME_WINDOW = 10000,
    parameter int PRECISION = PRECISION_CONV4
)(
    input  logic                  clk,
    input  logic                  reset,
    input event_type              in_event,
    input  logic  [PRECISION-1:0] in_features [OUTPUT_DIM-1:0],
    output logic [PRECISION-1 :0] out_features [OUTPUT_DIM-1 : 0],
    output logic                  out_valid
);
    logic [PRECISION-1:0] max_feature [OUTPUT_DIM-1:0] = '{default: '0};;
    logic [T_WIDTH-1:0]   threshold = TIME_WINDOW;
    logic                 reset_max;

    genvar i;
    generate
        for (i = 0; i < OUTPUT_DIM; i++) begin : calc_max
            always @(posedge clk) begin
                if (in_event.valid) begin
                    max_feature[i] <= (in_features[i] > max_feature[i]) ? in_features[i] : max_feature[i];
                end
                if (reset_max) begin
                    max_feature[i] <= in_features[i];
                end
                out_features[i] <= max_feature[i];
            end
        end
    endgenerate

    assign reset_max = (in_event.t > threshold) && in_event.valid;

    always @(posedge clk) begin
        if(reset) begin
            threshold <= TIME_WINDOW;
        end else begin
            if (reset_max) begin
                threshold <= threshold + TIME_WINDOW;
            end
            out_valid <= reset_max;
        end    
    end

endmodule
