`timescale 1ns / 1ps

import nas_pkg::*;

module gcnn_top #(
)( 
    input logic                       clk,
    input logic                       reset,
    input logic [T_WIDTH-1: 0]        t, 
    input logic [F_WIDTH-1: 0]        f, 
    input logic                       p,
    input logic                       is_valid,
    output logic                      is_ready,
//    output logic                      out_valid,
//    output logic [PRECISION_GEN-1 :0] out_conf,
//    output logic [PRECISION_GEN-1 :0] out_cls [CLS_NUM-1:0]

    output event_type                   event_test,
    output edge_type [MAX_EDGES-1:0]    edges_test,
    output logic [PRECISION_GEN-1:0]    features_test [OUTPUT_DIM_1-1 : 0]
);

    localparam string MEMORY_DIR_PATH = "/home/pwz/Repo/NEW_IMPL/NAS-GNN-KWS/HW/mem/";
    localparam string INIT_PATH_CONV1 = {MEMORY_DIR_PATH, "conv1.mem"};
    localparam string INIT_PATH_CONV2_W = {MEMORY_DIR_PATH, "conv2_w.mem"};
    localparam string INIT_PATH_CONV2_B = {MEMORY_DIR_PATH, "conv2_b.mem"};
    localparam string INIT_PATH_CONV3_W = {MEMORY_DIR_PATH, "conv3_w.mem"};
    localparam string INIT_PATH_CONV3_B = {MEMORY_DIR_PATH, "conv3_b.mem"};
    localparam string INIT_PATH_CONV4_W = {MEMORY_DIR_PATH, "conv4_w.mem"};
    localparam string INIT_PATH_CONV4_B = {MEMORY_DIR_PATH, "conv4_b.mem"};

    localparam CONV1_MULTIPLIER_DIFF_T = 73070576;
    localparam CONV1_MULTIPLIER_OUT = 47337484;
    localparam CONV1_ZERO_POINT_IN = 85;
    localparam CONV1_ZERO_POINT_OUT = 154;
    localparam CONV1_ZERO_POINT_WEIGHT = 177;      
    localparam logic [7:0] CONV1_SCALE_IN [20:0] = {0,8,17,25,34,42,51,59,68,76,170,162,153,145,136,128,119,111,102,94,85};

    localparam CONV2_MULTIPLIER_DIFF_T = 25842100;
    localparam CONV2_MULTIPLIER_OUT = 77634224;
    localparam CONV2_ZERO_POINT_IN = 154;
    localparam CONV2_ZERO_POINT_OUT = 107;
    localparam CONV2_ZERO_POINT_WEIGHT = 96;       
    localparam logic [7:0] CONV2_SCALE_IN [20:0] = {124,127,130,133,136,139,142,145,148,151,184,181,178,175,172,169,166,163,160,157,154};

    localparam CONV3_MULTIPLIER_DIFF_T = 18817560;
    localparam CONV3_MULTIPLIER_OUT = 40508052;
    localparam CONV3_ZERO_POINT_IN = 107;
    localparam CONV3_ZERO_POINT_OUT = 55;
    localparam CONV3_ZERO_POINT_WEIGHT = 86;       
    localparam logic [7:0] CONV3_SCALE_IN [20:0] = {85,87,89,92,94,96,98,100,103,105,129,127,125,122,120,118,116,114,111,109,107};

    localparam CONV4_MULTIPLIER_DIFF_T = 9043247;
    localparam CONV4_MULTIPLIER_OUT = 31633292;
    localparam CONV4_ZERO_POINT_IN = 55;
    localparam CONV4_ZERO_POINT_OUT = 83;
    localparam CONV4_ZERO_POINT_WEIGHT = 132;   
    localparam logic [7:0] CONV4_SCALE_IN [20:0] = {44,46,47,48,49,50,51,52,53,54,66,64,63,62,61,60,59,58,57,56,55};

    event_type                   event_to_conv1, event_to_conv2, event_to_conv3, event_to_conv4, event_to_pool;
    event_type                   event_to_buff1, event_to_buff2, event_to_buff3, event_to_buff4;
    edge_type [MAX_EDGES-1:0]    edges_to_conv1, edges_to_conv2, edges_to_conv3, edges_to_conv4;
    edge_type [MAX_EDGES-1:0]    edges_to_buff1, edges_to_buff2, edges_to_buff3, edges_to_buff4;
    logic [PRECISION_GEN-1:0]    f_feature;
    logic [PRECISION_GEN-1:0]    t_feature;
    logic [PRECISION_GEN-1:0]    p_feature;
    logic [PRECISION_GEN-1:0]    features_to_conv1 [INPUT_DIM_1-1 : 0];
    logic [PRECISION_GEN-1:0]    features_to_buff1 [INPUT_DIM_1-1 : 0];
    logic [PRECISION_CONV1-1 :0] features_to_conv2 [OUTPUT_DIM_1-1 : 0];
    logic [PRECISION_CONV1-1 :0] features_to_buff2 [OUTPUT_DIM_1-1 : 0];
    logic [PRECISION_CONV1-1 :0] features_to_conv3 [OUTPUT_DIM_1-1 : 0];
    logic [PRECISION_CONV1-1 :0] features_to_buff3 [OUTPUT_DIM_1-1 : 0];
    logic [PRECISION_CONV2-1 :0] features_to_conv4 [OUTPUT_DIM_2-1 : 0];
    logic [PRECISION_CONV3-1 :0] features_to_buff4 [OUTPUT_DIM_3-1 : 0];
    logic [PRECISION_CONV4-1 :0] features_to_pool  [OUTPUT_DIM_4-1 : 0];
    logic [PRECISION_CONV4-1 :0] features_to_head  [OUTPUT_DIM_4-1 : 0];
    logic [$clog2(MAX_EDGES) :0] edge_cnt_to_conv1;
    logic [$clog2(MAX_EDGES) :0] edge_cnt_to_buff1;
    logic [$clog2(MAX_EDGES) :0] edge_cnt_to_conv2;
    logic [$clog2(MAX_EDGES) :0] edge_cnt_to_buff2;
    logic [$clog2(MAX_EDGES) :0] edge_cnt_to_conv3;
    logic [$clog2(MAX_EDGES) :0] edge_cnt_to_buff3;
    logic [$clog2(MAX_EDGES) :0] edge_cnt_to_conv4;
    logic [$clog2(MAX_EDGES) :0] edge_cnt_to_buff4;

    logic gen_valid, gen_next;

    handshake u_handshake (
        .clk       ( clk                   ),
        .reset     ( reset                 ),
        .is_ready  ( is_ready              ),
        .is_valid  ( is_valid              ),
        .out_valid ( gen_valid             ),
        .get_next  ( event_to_conv1.valid  )
    );

    generate_graph u_gen_graph (
        .clk        ( clk                ),
        .reset      ( reset              ),
        .t          ( t                  ),
        .f          ( f                  ),
        .p          ( p                  ),
        .is_valid   ( gen_valid          ),
        .out_event  ( event_to_buff1    ),
        .out_edges  ( edges_to_buff1    ),
        .t_feature  ( t_feature          ),
        .f_feature  ( f_feature          ),
        .p_feature  ( p_feature          ),
        .edge_cnt   ( edge_cnt_to_buff1 )
    );

    logic buff2_empty, buff2_empty_reg, buff3_empty, buff4_empty;
    assign features_to_buff1[0] = t_feature;
    assign features_to_buff1[1] = f_feature;
    assign features_to_buff1[2] = p_feature;

    buffer #(
        .FEATURE_DIM  ( INPUT_DIM_1 )
    ) u_buff1 (
        .clk          ( clk                     ),
        .reset        ( reset                   ),
        .in_event     ( event_to_buff1          ),
        .in_edges     ( edges_to_buff1          ),
        .in_features  ( features_to_buff1       ),
        .in_edge_cnt  ( edge_cnt_to_buff1       ),
        .out_event    ( event_to_conv1          ),
        .out_edges    ( edges_to_conv1          ),
        .out_features ( features_to_conv1       ),
        .out_edge_cnt ( edge_cnt_to_conv1       ),
        .get_next     ( event_to_conv2.valid )
    );

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
         .in_edge_cnt  ( edge_cnt_to_conv1 ),
         .out_event    ( event_to_buff2    ),
         .out_edges    ( edges_to_buff2    ),
         .out_features ( features_to_buff2 ),
         .out_edge_cnt ( edge_cnt_to_buff2 )
     );

    buffer #(
        .FEATURE_DIM  ( OUTPUT_DIM_1 )
    ) u_buff2 (
        .clk          ( clk                  ),
        .reset        ( reset                ),
        .in_event     ( event_to_buff2       ),
        .in_edges     ( edges_to_buff2       ),
        .in_features  ( features_to_buff2    ),
        .in_edge_cnt  ( edge_cnt_to_buff2    ),
        .out_event    ( event_to_conv2       ),
        .out_edges    ( edges_to_conv2       ),
        .out_features ( features_to_conv2    ),
        .out_edge_cnt ( edge_cnt_to_conv2    ),
        .get_next     ( event_to_conv3.valid )

    );

      convolution_sparse #(
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
          .INIT_PATH_W       ( INIT_PATH_CONV2_W       ),
          .INIT_PATH_B       ( INIT_PATH_CONV2_B       )
      ) u_conv2 (
          .clk          ( clk               ),
          .reset        ( reset             ),
          .in_event     ( event_to_conv2    ),
          .in_edges     ( edges_to_conv2    ),
          .in_features  ( features_to_conv2 ),
          .in_edge_cnt  ( edge_cnt_to_conv2 ),
          .out_event    ( event_to_buff3    ),
          .out_edges    ( edges_to_buff3    ),
          .out_features ( features_to_buff3 ),
          .out_edge_cnt ( edge_cnt_to_buff3 )
      );

    buffer #(
        .FEATURE_DIM  ( OUTPUT_DIM_2 )
    ) u_buff3 (
        .clk          ( clk                  ),
        .reset        ( reset                ),
        .in_event     ( event_to_buff3       ),
        .in_edges     ( edges_to_buff3       ),
        .in_features  ( features_to_buff3    ),
        .in_edge_cnt  ( edge_cnt_to_buff3    ),
        .out_event    ( event_to_conv3       ),
        .out_edges    ( edges_to_conv3       ),
        .out_features ( features_to_conv3    ),
        .out_edge_cnt ( edge_cnt_to_conv3    ),
        .get_next     ( event_to_conv4.valid )

    );

     convolution_sparse #(
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
         .INIT_PATH_W       ( INIT_PATH_CONV3_W       ),
         .INIT_PATH_B       ( INIT_PATH_CONV3_B       )
      ) u_conv3 (
          .clk          ( clk               ),
          .reset        ( reset             ),
          .in_event     ( event_to_conv3    ),
          .in_edges     ( edges_to_conv3    ),
          .in_features  ( features_to_conv3 ),
          .in_edge_cnt  ( edge_cnt_to_conv3 ),
          .out_event    ( event_to_buff4    ),
          .out_edges    ( edges_to_buff4    ),
          .out_features ( features_to_buff4 ),
          .out_edge_cnt ( edge_cnt_to_buff4 )
      );

    buffer #(
        .FEATURE_DIM  ( OUTPUT_DIM_3 )
    ) u_buff4 (
        .clk          ( clk               ),
        .reset        ( reset             ),
        .in_event     ( event_to_buff4    ),
        .in_edges     ( edges_to_buff4    ),
        .in_features  ( features_to_buff4 ),
        .in_edge_cnt  ( edge_cnt_to_buff4 ),
        .out_event    ( event_to_conv4    ),
        .out_edges    ( edges_to_conv4    ),
        .out_features ( features_to_conv4 ),
        .out_edge_cnt ( edge_cnt_to_conv4 ),
        .get_next     ( event_test.valid  )

    );

     convolution_sparse #(
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
         .INIT_PATH_W       ( INIT_PATH_CONV4_W       ),
         .INIT_PATH_B       ( INIT_PATH_CONV4_B       )
     ) u_conv4 (
         .clk          ( clk               ),
         .reset        ( reset             ),
         .in_event     ( event_to_conv4    ),
         .in_edges     ( edges_to_conv4    ),
         .in_features  ( features_to_conv4 ),
         .in_edge_cnt  ( edge_cnt_to_conv4 ),
         .out_event    ( event_test    ),
         .out_edges    ( edges_test    ),
         .out_features ( features_test )
//         .out_event    ( event_to_pool     ),
//         .out_edges    (                   ),
//         .out_features ( features_to_pool  )
     );

// //    assign event_test = event_to_conv3;
// //    assign edges_test = edges_to_conv3;
// //    assign features_test = features_to_conv3;

//     logic head_valid;

//     maxpool #(
//         .ZERO_POINT ( CONV4_ZERO_POINT_OUT )
//     ) u_pool (
//         .clk          ( clk              ),
//         .reset        ( reset            ),
//         .in_event     ( event_to_pool    ),
//         .in_features  ( features_to_pool ),
//         .out_features ( features_to_head ),
//         .out_valid    ( head_valid       )
//      );

//     gru_head u_head (
//         .clk         ( clk              ),
//         .reset       ( reset            ),
//         .in_valid    ( head_valid       ),
//         .in_features ( features_to_head ),
//         .out_conf    ( out_conf         ),
//         .out_cls     ( out_cls          ),
//         .out_valid   ( out_valid        )
//      );

endmodule : gcnn_top
