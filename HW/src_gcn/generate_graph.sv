`timescale 1ns / 1ps

import graph_pkg::*;

module generate_graph #(
)( 
    input  logic                          clk,
    input  logic                          reset,
    input  logic      [T_WIDTH-1: 0]      t,
    input  logic      [F_WIDTH-1: 0]      f,
    input  logic                          is_valid,
    input  logic                          is_last,

    output event_type                     out_event,
    output edge_type  [MAX_EDGES-1 : 0]   out_edges,
    output logic      [PRECISION_GEN-1:0] t_feature,
    output logic      [PRECISION_GEN-1:0] f_feature
);

    event_type event_to_edges_gen,event_to_feature_gen;
    edge_type [MAX_EDGES-1 : 0] edges_to_feature_gen;

    fifo_handler #() u_input_fifo (
        .clk           ( clk                ),
        .reset         ( reset              ),
        .t             ( t                  ),
        .f             ( f                  ),
        .is_valid      ( is_valid           ),
        .is_last       ( is_last            ),
        .out_event     ( event_to_edges_gen )
    );

    edges_gen #() u_edges_gen (
        .clk           ( clk                  ),
        .reset         ( reset                ),
        .in_event      ( event_to_edges_gen   ),
        .out_event     ( event_to_feature_gen ),
        .out_edges     ( edges_to_feature_gen )
        
    );
    
    feature_gen #(
        .T_MULTIPLIER ( GEN_MULTIPLIER_T ),
        .F_MULTIPLIER ( GEN_MULTIPLIER_F ),
        .ZERO_POINT   ( GEN_ZERO_POINT   )
    ) u_feature_gen (
        .clk           ( clk                  ),
        .reset         ( reset                ),
        .in_event      ( event_to_feature_gen ),
        .in_edges      ( edges_to_feature_gen ),
        .out_event     ( out_event            ),
        .out_edges     ( out_edges            ),
        .t_feature     ( t_feature            ),
        .f_feature     ( f_feature            )
    );

endmodule
