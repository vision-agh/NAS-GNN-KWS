`timescale 1ns / 1ps

import nas_pkg::*;

module gcnn_top #(
)( 
    input logic                clk,
    input logic                reset,
    input logic [T_WIDTH-1: 0] t, 
    input logic [F_WIDTH-1: 0] f, 
    input logic                is_valid,
    output logic                      out_valid,
    output logic [PRECISION_GEN-1 :0] out_conf,
    output logic [PRECISION_GEN-1 :0]  out_cls [CLS_NUM-1:0]

//    output event_type                   event_test,
//    output edge_type [MAX_EDGES-1:0]    edges_test,
//    output logic [PRECISION_GEN-1:0]    features_test [OUTPUT_DIM_1-1 : 0]
);

    localparam string MEMORY_DIR_PATH = "/home/pwz/Repo/NAS-GCN-KWS/HW/mem/";
    localparam string INIT_PATH_CONV1 = {MEMORY_DIR_PATH, "conv1.mem"};
    localparam string INIT_PATH_CONV2 = {MEMORY_DIR_PATH, "conv2.mem"};
    localparam string INIT_PATH_CONV3 = {MEMORY_DIR_PATH, "conv3.mem"};
    localparam string INIT_PATH_CONV4 = {MEMORY_DIR_PATH, "conv4.mem"};

    localparam CONV1_MULTIPLIER_DIFF_T = 53515020;
    localparam CONV1_MULTIPLIER_OUT = 30749878;
    localparam CONV1_ZERO_POINT_IN = 125;
    localparam CONV1_ZERO_POINT_OUT = 156;
    localparam CONV1_ZERO_POINT_WEIGHT = 152;
    localparam logic [7:0] CONV1_SCALE_IN [21:0] = {125,113,100,88,75,63,50,38,25,13,0,250,237,225,212,200,187,175,162,150,137,125};

    localparam CONV2_MULTIPLIER_DIFF_T = 9396243;
    localparam CONV2_MULTIPLIER_OUT = 68070312;
    localparam CONV2_ZERO_POINT_IN = 156;
    localparam CONV2_ZERO_POINT_OUT = 161;
    localparam CONV2_ZERO_POINT_WEIGHT = 107;
    localparam logic [7:0] CONV2_SCALE_IN [21:0] = {156,154,152,149,147,145,143,141,138,136,134,178,176,174,171,169,167,165,163,160,158,156};

    localparam CONV3_MULTIPLIER_DIFF_T = 10573274;
    localparam CONV3_MULTIPLIER_OUT = 67359312;
    localparam CONV3_ZERO_POINT_IN = 161;
    localparam CONV3_ZERO_POINT_OUT = 129;
    localparam CONV3_ZERO_POINT_WEIGHT = 99;
    localparam logic [7:0] CONV3_SCALE_IN [21:0] = {161,159,156,154,151,149,146,144,141,139,136,186,183,181,178,176,173,171,168,166,163,161};

    localparam CONV4_MULTIPLIER_DIFF_T = 10041837;
    localparam CONV4_MULTIPLIER_OUT = 39348392;
    localparam CONV4_ZERO_POINT_IN = 129;
    localparam CONV4_ZERO_POINT_OUT = 136;
    localparam CONV4_ZERO_POINT_WEIGHT = 139;
    localparam logic [7:0] CONV4_SCALE_IN [21:0] = {129,127,124,122,120,117,115,113,110,108,106,152,150,148,145,143,141,138,136,134,131,129};

    event_type                   event_to_conv1, event_to_conv2, event_to_conv3, event_to_conv4, event_to_pool;
    edge_type [MAX_EDGES-1:0]    edges_to_conv1, edges_to_conv2, edges_to_conv3, edges_to_conv4;
    logic [PRECISION_GEN-1:0]    f_feature;
    logic [PRECISION_GEN-1:0]    t_feature;
    logic [PRECISION_GEN-1:0]    features_to_conv1 [INPUT_DIM_1-1 : 0];
    logic [PRECISION_CONV1-1 :0] features_to_conv2 [OUTPUT_DIM_1-1 : 0];
    logic [PRECISION_CONV2-1 :0] features_to_conv3 [OUTPUT_DIM_2-1 : 0];
    logic [PRECISION_CONV3-1 :0] features_to_conv4 [OUTPUT_DIM_3-1 : 0];
    logic [PRECISION_CONV4-1 :0] features_to_pool   [OUTPUT_DIM_4-1 : 0];
    logic [PRECISION_CONV4-1 :0] features_to_head   [OUTPUT_DIM_4-1 : 0];

    generate_graph u_gen_graph (
        .clk        ( clk            ),
        .reset      ( reset          ),
        .t          ( t              ),
        .f          ( f              ),
        .is_valid   ( is_valid       ),
        // .is_last    ( is_last        ),
        .out_event  ( event_to_conv1 ),
        .out_edges  ( edges_to_conv1 ),
        .t_feature  ( t_feature      ),
        .f_feature  ( f_feature      )
    );

    assign features_to_conv1[0] = t_feature;
    assign features_to_conv1[1] = f_feature;

     convolution #(
         .PRECISION_IN      ( PRECISION_GEN           ),
         .PRECISION_OUT     ( PRECISION_CONV1         ),
         .INPUT_DIM         ( INPUT_DIM_1             ),
         .OUTPUT_DIM        ( OUTPUT_DIM_1            ),
         .MULTIPLIER_DIFF_T ( CONV1_MULTIPLIER_DIFF_T ),
         .ZERO_POINT_IN     ( CONV1_ZERO_POINT_IN     ),
         .ZERO_POINT_OUT    ( CONV1_ZERO_POINT_OUT    ),
         .MULTIPLIER_OUT    ( CONV1_MULTIPLIER_OUT    ),
         .ZERO_POINT_WEIGHT ( CONV1_ZERO_POINT_WEIGHT ),
         .SCALE_IN          ( CONV1_SCALE_IN          ),
         .INIT_PATH         ( INIT_PATH_CONV1         )
     ) u_conv1 (
         .clk          ( clk               ),
         .reset        ( reset             ),
         .in_event     ( event_to_conv1    ),
         .in_edges     ( edges_to_conv1    ),
         .in_features  ( features_to_conv1 ),
         .out_event    ( event_to_conv2    ),
         .out_edges    ( edges_to_conv2    ),
         .out_features ( features_to_conv2 )

     );

     convolution_reversed #(
         .PRECISION_IN      ( PRECISION_CONV1         ),
         .PRECISION_OUT     ( PRECISION_CONV2         ),
         .INPUT_DIM         ( OUTPUT_DIM_1            ),
         .OUTPUT_DIM        ( OUTPUT_DIM_2            ),
         .MULTIPLIER_DIFF_T ( CONV2_MULTIPLIER_DIFF_T ),
         .ZERO_POINT_IN     ( CONV2_ZERO_POINT_IN     ),
         .ZERO_POINT_OUT    ( CONV2_ZERO_POINT_OUT    ),
         .MULTIPLIER_OUT    ( CONV2_MULTIPLIER_OUT    ),
         .ZERO_POINT_WEIGHT ( CONV2_ZERO_POINT_WEIGHT ),
         .SCALE_IN          ( CONV2_SCALE_IN          ),
         .INIT_PATH         ( INIT_PATH_CONV2         )
     ) u_conv2 (
         .clk          ( clk               ),
         .reset        ( reset             ),
         .in_event     ( event_to_conv2    ),
         .in_edges     ( edges_to_conv2    ),
         .in_features  ( features_to_conv2 ),
         .out_event    ( event_to_conv3    ),
         .out_edges    ( edges_to_conv3    ),
         .out_features ( features_to_conv3 )
     );

    convolution_reversed #(
        .PRECISION_IN      ( PRECISION_CONV2         ),
        .PRECISION_OUT     ( PRECISION_CONV3         ),
        .INPUT_DIM         ( OUTPUT_DIM_2            ),
        .OUTPUT_DIM        ( OUTPUT_DIM_3            ),
        .MULTIPLIER_DIFF_T ( CONV3_MULTIPLIER_DIFF_T ),
        .ZERO_POINT_IN     ( CONV3_ZERO_POINT_IN     ),
        .ZERO_POINT_OUT    ( CONV3_ZERO_POINT_OUT    ),
        .MULTIPLIER_OUT    ( CONV3_MULTIPLIER_OUT    ),
        .ZERO_POINT_WEIGHT ( CONV3_ZERO_POINT_WEIGHT ),
        .SCALE_IN          ( CONV3_SCALE_IN          ),
        .INIT_PATH         ( INIT_PATH_CONV3         )
    ) u_conv3 (
        .clk          ( clk               ),
        .reset        ( reset             ),
        .in_event     ( event_to_conv3    ),
        .in_edges     ( edges_to_conv3    ),
        .in_features  ( features_to_conv3 ),
        .out_event    ( event_to_conv4    ),
        .out_edges    ( edges_to_conv4    ),
        .out_features ( features_to_conv4 )
    );

    convolution_reversed #(
        .PRECISION_IN      ( PRECISION_CONV3         ),
        .PRECISION_OUT     ( PRECISION_CONV4         ),
        .INPUT_DIM         ( OUTPUT_DIM_3            ),
        .OUTPUT_DIM        ( OUTPUT_DIM_4            ),
        .MULTIPLIER_DIFF_T ( CONV4_MULTIPLIER_DIFF_T ),
        .ZERO_POINT_IN     ( CONV4_ZERO_POINT_IN     ),
        .ZERO_POINT_OUT    ( CONV4_ZERO_POINT_OUT    ),
        .MULTIPLIER_OUT    ( CONV4_MULTIPLIER_OUT    ),
        .ZERO_POINT_WEIGHT ( CONV4_ZERO_POINT_WEIGHT ),
        .SCALE_IN          ( CONV4_SCALE_IN          ),
        .INIT_PATH         ( INIT_PATH_CONV4         )
    ) u_conv4 (
        .clk          ( clk               ),
        .reset        ( reset             ),
        .in_event     ( event_to_conv4    ),
        .in_edges     ( edges_to_conv4    ),
        .in_features  ( features_to_conv4 ),
//         .out_event    ( event_test    ),
//         .out_edges    ( edges_test    ),
//         .out_features ( features_test )
        .out_event    ( event_to_pool     ),
        .out_edges    (                   ),
        .out_features ( features_to_pool  )
    );

//    assign event_test = event_to_conv3;
//    assign edges_test = edges_to_conv3;
//    assign features_test = features_to_conv3;

    logic head_valid;

    maxpool u_pool (
        .clk          ( clk              ),
        .reset        ( reset            ),
        .in_event     ( event_to_pool    ),
        .in_features  ( features_to_pool ),
        .out_features ( features_to_head ),
        .out_valid    ( head_valid       )
     );

    gru_head u_head (
        .clk         ( clk              ),
        .reset       ( reset            ),
        .in_valid    ( head_valid       ),
        .in_features ( features_to_head ),
        .out_conf    ( out_conf         ),
        .out_cls     ( out_cls          ),
        .out_valid   ( out_valid        )
     );

endmodule : gcnn_top
