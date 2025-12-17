`timescale 1ns / 1ps

import graph_pkg::*;

module top #(
)( 
    input logic                clk,
    input logic                reset,
    input logic [T_WIDTH-1: 0] t, 
    input logic [F_WIDTH-1: 0] f, 
    input logic                is_valid,
    input logic                is_last,

    output logic                      out_valid,
    output logic [PRECISION_GEN-1 :0] out_conf,
    output logic [(8*20)-1 :0]        out_cls
    //output logic [PRECISION_GEN-1 :0]  out_cls [CLS_NUM-1:0]

//    output event_type                   event_test,
//    output edge_type [MAX_EDGES-1:0]    edges_test,
//    output logic [PRECISION_GEN-1:0]    features_test [OUTPUT_DIM_1-1 : 0]

//   output logic  [$clog2(OUTPUT_DIM_4)-1: 0] out_address, 
//   output logic  [PRECISION_CONV4-1:0]       out_feature,
//   output logic                              out_valid
);

    localparam string MEMORY_DIR_PATH = "/home/pwz/Repo/gcnn-audio-fpga/HW/mem/";
    localparam string INIT_PATH_CONV1 = {MEMORY_DIR_PATH, "conv1.mem"};
    localparam string INIT_PATH_CONV2 = {MEMORY_DIR_PATH, "conv2.mem"};
    localparam string INIT_PATH_CONV3 = {MEMORY_DIR_PATH, "conv3.mem"};
    localparam string INIT_PATH_CONV4 = {MEMORY_DIR_PATH, "conv4.mem"};

    localparam CONV1_MULTIPLIER_DIFF_T = 958724;
    localparam CONV1_MULTIPLIER_OUT = 101662264;
    localparam CONV1_ZERO_POINT_IN = 32;
    localparam CONV1_ZERO_POINT_OUT = 132;
    localparam CONV1_ZERO_POINT_WEIGHT = 152;
    localparam logic [7:0] CONV1_SCALE_IN [21:0] = {32, 29, 26, 22, 19, 16, 13, 10, 6, 3, 0, 64, 61, 58, 54, 51, 48, 45, 42, 38, 35, 32};

    localparam CONV2_MULTIPLIER_DIFF_T = 53777;
    localparam CONV2_MULTIPLIER_OUT = 30159156;
    localparam CONV2_ZERO_POINT_IN = 132;
    localparam CONV2_ZERO_POINT_OUT = 135;
    localparam CONV2_ZERO_POINT_WEIGHT = 146;
    localparam logic [7:0] CONV2_SCALE_IN [21:0] = {132, 132, 132, 131, 131, 131, 131, 131, 131, 130, 130, 134, 134, 133, 133, 133, 133, 133, 133, 132, 132, 132};

    localparam CONV3_MULTIPLIER_DIFF_T = 48931;
    localparam CONV3_MULTIPLIER_OUT = 24604964;
    localparam CONV3_ZERO_POINT_IN = 135;
    localparam CONV3_ZERO_POINT_OUT = 130;
    localparam CONV3_ZERO_POINT_WEIGHT = 107;
    localparam logic [7:0] CONV3_SCALE_IN [21:0] = {135, 135, 135, 135, 134, 134, 134, 134, 134, 134, 133, 137, 136, 136, 136, 136, 136, 136, 135, 135, 135, 135};

    localparam CONV4_MULTIPLIER_DIFF_T = 43390;
    localparam CONV4_MULTIPLIER_OUT = 45899688;
    localparam CONV4_ZERO_POINT_IN = 130;
    localparam CONV4_ZERO_POINT_OUT = 119;
    localparam CONV4_ZERO_POINT_WEIGHT = 149;
    localparam logic [7:0] CONV4_SCALE_IN [21:0] = {130, 130, 130, 130, 129, 129, 129, 129, 129, 129, 129, 131, 131, 131, 131, 131, 131, 131, 130, 130, 130, 130};

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
        .is_last    ( is_last        ),
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

    logic head_valid;

    maxpool u_pool (
        .clk          ( clk              ),
        .reset        ( reset            ),
        .in_event     ( event_to_pool    ),
        .in_features  ( features_to_pool ),
        .out_features ( features_to_head ),
        .out_valid    ( head_valid       )
     );

    logic [PRECISION_GEN-1 :0]  out_cls_type [CLS_NUM-1:0];
    gru_head u_head (
        .clk         ( clk              ),
        .reset       ( reset            ),
        .in_valid    ( head_valid       ),
        .in_features ( features_to_head ),
        .out_conf    ( out_conf         ),
        .out_cls     ( out_cls_type     ),
        .out_valid   ( out_valid        )
     );

    genvar i;
    generate
      for (i = 0; i < 20; i++) begin
        assign out_cls[i*8 +: 8] = out_cls_type[i];
      end
    endgenerate

endmodule : top
