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
    input  logic  [PRECISION-1:0] in_features [OUTPUT_DIM-1:0],
    output logic [PRECISION-1 :0] out_features [OUTPUT_DIM-1 : 0],
    output logic                  out_valid
);
    logic [PRECISION-1:0] max_feature [OUTPUT_DIM-1:0] = '{default: ZERO_POINT};;
    logic [63:0]   threshold = TIME_WINDOW;
    logic          reset_max;
    logic [63:0]   time_now = 0;

    genvar i;
    generate
        for (i = 0; i < OUTPUT_DIM; i++) begin : calc_max
            always @(posedge clk) begin
                if (in_event.valid) begin
                    max_feature[i] <= (in_features[i] > max_feature[i]) ? in_features[i] : max_feature[i];
                    time_now <= in_event.t*1000;
                end
                else begin
                    if (time_now != 0) begin
                        time_now <= time_now + 5;
                    end
                end
                if (reset_max) begin
                    if (in_event.valid) max_feature[i] <= in_features[i];
                    else max_feature[i] <= ZERO_POINT;
                end
                out_features[i] <= max_feature[i];
            end
        end
    endgenerate

    assign reset_max = (time_now > threshold);

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
