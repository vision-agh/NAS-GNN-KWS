`timescale 1ns / 1ps

import nas_pkg::*;

module buffer #(
    parameter int PRECISION_IN               = nas_pkg::PRECISION_CONV1,
    parameter int PRECISION_OUT              = nas_pkg::PRECISION_CONV1,
    parameter int INPUT_DIM                  = 72,
    parameter int OUTPUT_DIM                 = 72
)(
    input logic clk,
    input logic reset,
    input event_type                   in_event,
    output logic                       get_next,
    input edge_type  [MAX_EDGES-1:0]   in_edges,
    input logic [PRECISION_IN-1 :0]    in_features [INPUT_DIM-1 : 0],
    input logic [$clog2(MAX_EDGES) :0] in_edge_cnt,

    output event_type                   out_event,
    output edge_type  [MAX_EDGES-1:0]   out_edges,
    output logic [PRECISION_OUT-1 :0]   out_features [OUTPUT_DIM-1 : 0],
    output logic [$clog2(MAX_EDGES) :0] out_edge_cnt,
    input logic                         out_ready
);

    logic has_event = 0;

    always @(posedge clk) begin
        get_next <= '0;
        if (in_event.valid) begin
            out_event <= in_event;
            out_edges <= in_edges;
            out_features <= in_features;
            out_edge_cnt <= in_edge_cnt;
            has_event <= 1;
        end
        out_event.valid <= '0;
        if (out_ready && has_event) begin
            has_event <= '0;
            out_event.valid <= '1;
            get_next <= '1;
        end
    end

endmodule