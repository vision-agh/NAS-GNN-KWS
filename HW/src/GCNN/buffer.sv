`timescale 1ns / 1ps

import nas_pkg::*;

module buffer #(
    parameter int PRECISION_IN               = nas_pkg::PRECISION_CONV1,
    parameter int PRECISION_OUT              = nas_pkg::PRECISION_CONV1,
    parameter int FEATURE_DIM                = 72
)(
    input logic clk,
    input logic reset,

    input get_next,

    input event_type                   in_event,
    input edge_type  [MAX_EDGES-1:0]   in_edges,
    input logic [PRECISION_IN-1 :0]    in_features [FEATURE_DIM-1 : 0],
    input logic [$clog2(MAX_EDGES) :0] in_edge_cnt,

    output event_type                   out_event,
    output edge_type  [MAX_EDGES-1:0]   out_edges,
    output logic [PRECISION_OUT-1 :0]   out_features [FEATURE_DIM-1 : 0],
    output logic [$clog2(MAX_EDGES) :0] out_edge_cnt
);

    event_type                   reg_event;
    edge_type  [MAX_EDGES-1:0]   reg_edges;
    logic [PRECISION_IN-1 :0]    reg_features [FEATURE_DIM-1 : 0];
    logic [$clog2(MAX_EDGES) :0] reg_edge_cnt;
    logic is_ready;
    logic is_empty;

    always @(posedge clk) begin
        if (reset) begin
            is_ready <= 1'b1;
            is_empty <= 1'b1;
        end
        else begin
            if (get_next_reg) begin
                is_ready <= '1;
            end
            
            if (in_event.valid) begin
                is_empty <= 1'b0;
                reg_event <= in_event;
                reg_edges <= in_edges;
                reg_features <= in_features;
                reg_edge_cnt <= in_edge_cnt;
            end
            out_event.valid <= '0;
            if (is_ready && !is_empty) begin
                is_ready <= '0;
                is_empty <= 1'b1;
                out_event <= reg_event;
                out_edges <= reg_edges;
                out_features <= reg_features;
                out_edge_cnt <= reg_edge_cnt;
            end
            
            
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            is_empty <= 1;
            out_event.valid <= '0;
        end
        else begin

            

        end
    end


    delay_module #(
        .N        ( 1  ),
        .DELAY    ( 5  )
    ) delay_enb (
        .clk   ( clk          ),
        .idata ( get_next     ),
        .odata ( get_next_reg )
    );


endmodule