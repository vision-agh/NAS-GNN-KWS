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
    input  logic [15 : 0]             idx_time,
    input  logic [T_WIDTH-1 : 0]      last_time,
    output logic                      is_ready,
    output logic                      out_valid,
    output logic [PRECISION_GEN-1 :0] out_conf,
    output logic [(PRECISION_GEN*CLS_NUM)-1 :0] out_cls

//    output event_type                   event_test,
//    output edge_type [MAX_EDGES-1:0]    edges_test,
//    output logic [PRECISION_GEN-1:0]    features_test [OUTPUT_DIM_1-1 : 0]
);

    localparam string MEMORY_DIR_PATH = "/home/pwz/Repo/NEW_IMPL/NAS-GNN-KWS/HW/mem/";
    localparam string INIT_PATH_CONV1 = {MEMORY_DIR_PATH, "conv1.mem"};
    localparam string INIT_PATH_CONV2_W = {MEMORY_DIR_PATH, "conv2_w.mem"};
    localparam string INIT_PATH_CONV2_B = {MEMORY_DIR_PATH, "conv2_b.mem"};
    localparam string INIT_PATH_CONV3_W = {MEMORY_DIR_PATH, "conv3_w.mem"};
    localparam string INIT_PATH_CONV3_B = {MEMORY_DIR_PATH, "conv3_b.mem"};
    localparam string INIT_PATH_CONV4_W = {MEMORY_DIR_PATH, "conv4_w.mem"};
    localparam string INIT_PATH_CONV4_B = {MEMORY_DIR_PATH, "conv4_b.mem"};

    localparam CONV1_MULTIPLIER_DIFF_T = 84884488;
    localparam CONV1_MULTIPLIER_OUT = 36650108;
    localparam CONV1_ZERO_POINT_IN = 99;
    localparam CONV1_ZERO_POINT_OUT = 157;
    localparam CONV1_ZERO_POINT_WEIGHT = 151;      
    localparam logic [7:0] CONV1_SCALE_IN [10:0] = {0, 20, 40, 59, 79, 198, 178, 158, 139, 119, 99};

    localparam CONV2_MULTIPLIER_DIFF_T = 20096254;
    localparam CONV2_MULTIPLIER_OUT = 75262432;
    localparam CONV2_ZERO_POINT_IN = 157;
    localparam CONV2_ZERO_POINT_OUT = 124;
    localparam CONV2_ZERO_POINT_WEIGHT = 97;       
    localparam logic [7:0] CONV2_SCALE_IN [10:0] = {134,138,143,148,152,180,176,171,166,162,157};

    localparam CONV3_MULTIPLIER_DIFF_T = 23465478;
    localparam CONV3_MULTIPLIER_OUT = 29568546;
    localparam CONV3_ZERO_POINT_IN = 124;
    localparam CONV3_ZERO_POINT_OUT = 72;
    localparam CONV3_ZERO_POINT_WEIGHT = 87;       
    localparam logic [7:0] CONV3_SCALE_IN [10:0] = {97, 102, 108, 113, 119, 151, 146, 140, 135, 129, 124};

    localparam CONV4_MULTIPLIER_DIFF_T = 9689040;
    localparam CONV4_MULTIPLIER_OUT = 35077416;
    localparam CONV4_ZERO_POINT_IN = 72;
    localparam CONV4_ZERO_POINT_OUT = 114;
    localparam CONV4_ZERO_POINT_WEIGHT = 130;   
    localparam logic [7:0] CONV4_SCALE_IN [10:0] = {61, 63, 65, 67, 70, 83, 81, 79, 77, 74, 72};

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
        .clk          ( clk                 ),
        .reset        ( reset               ),
        .in_event     ( event_to_buff4      ),
        .in_edges     ( edges_to_buff4      ),
        .in_features  ( features_to_buff4   ),
        .in_edge_cnt  ( edge_cnt_to_buff4   ),
        .out_event    ( event_to_conv4      ),
        .out_edges    ( edges_to_conv4      ),
        .out_features ( features_to_conv4   ),
        .out_edge_cnt ( edge_cnt_to_conv4   ),
        .get_next     ( event_to_pool.valid )

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
//         .out_event    ( event_test    ),
//         .out_edges    ( edges_test    ),
//         .out_features ( features_test )
         .out_event    ( event_to_pool     ),
         .out_edges    (                   ),
         .out_features ( features_to_pool  ),
         .out_edge_cnt (                   )
     );

     logic head_valid;

     maxpool #(
         .ZERO_POINT ( CONV4_ZERO_POINT_OUT )
     ) u_pool (
         .clk          ( clk              ),
         .reset        ( reset            ),
         .last_time    ( last_time        ),
         .idx_time     ( idx_time         ),
         .in_event     ( event_to_pool    ),
         .in_features  ( features_to_pool ),
         .out_features ( features_to_head ),
         .out_valid    ( head_valid       )
      );

    logic [(PRECISION_GEN)-1 :0] out_cls_reg [CLS_NUM-1:0];

     gru_head u_head (
         .clk         ( clk              ),
         .reset       ( reset            ),
         .in_valid    ( head_valid       ),
         .in_features ( features_to_head ),
         .out_conf    ( out_conf         ),
         .out_cls     ( out_cls_reg      ),
         .out_valid   ( out_valid        )
      );


    genvar i;
    generate begin
        for(i = 0; i< CLS_NUM; i++) begin  : assign_out
            assign out_cls[((i+1)*PRECISION_GEN)-1 : (i*PRECISION_GEN)] = out_cls_reg[i];
        end
    end
    endgenerate

endmodule : gcnn_top
