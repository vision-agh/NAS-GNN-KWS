`timescale 1ns / 1ps

import nas_pkg::*;

module convolution #(
    parameter int PRECISION_IN               = nas_pkg::PRECISION_CONV1,
    parameter int PRECISION_OUT              = nas_pkg::PRECISION_CONV1,
    parameter int INPUT_DIM                  = 2,
    parameter int OUTPUT_DIM                 = 64,
    parameter int MULTIPLIER_DIFF_T          = 214742, //good
    parameter int ZERO_POINT_IN              = 0,  //good
    parameter int ZERO_POINT_OUT             = 36533, //good
    parameter int MULTIPLIER_OUT             = 58670, //good
    parameter int ZERO_POINT_WEIGHT          = 30075,
    parameter string INIT_PATH               = "???",
    parameter logic [PRECISION_IN-1:0] SCALE_IN [20:0]   = { 32767, 29490, 26214, 22937, 19660, 16383, 13107, 9830, 6553, 3277, 0, 65534,
                                                             62257, 58981, 55704, 52427, 49150, 45874, 42597, 39320, 36044, 32767 }
)(
    input logic clk,
    input logic reset,
    input event_type                        in_event,
    input edge_type  [MAX_EDGES-1:0]        in_edges,
    input logic [PRECISION_IN-1 :0]         in_features [INPUT_DIM-1 : 0],
    input logic      [$clog2(MAX_EDGES) :0] in_edge_cnt,

    output event_type                        out_event,
    output edge_type  [MAX_EDGES-1:0]        out_edges,
    output logic [PRECISION_OUT-1 :0]        out_features [OUTPUT_DIM-1 : 0],
    output logic      [$clog2(MAX_EDGES) :0] out_edge_cnt
);

    typedef logic [PRECISION_IN-1 :0] features_type [INPUT_DIM-1 : 0];
    typedef logic [(PRECISION_IN*INPUT_DIM)-1 :0] memory_type;
    localparam AWIDTH = $clog2(NUM_CHANNEL);
    localparam DWIDTH = INPUT_DIM * PRECISION_IN;

    // Process:
    // cnt - save internal state
    // MRR - MemoryReadRequest
    // RM - ReadMemory


    // Internal state - ready on RM
    event_type                        event_reg;
    edge_type  [MAX_EDGES-1:0]        edges_reg;
    logic      [$clog2(MAX_EDGES) :0] edge_cnt_reg;
    logic [$clog2(MAX_EDGES/2) :0]    num_iter;
    features_type                     features_reg;

    // STATE MACHINE:
    // IDLE - wait
    // CONV - convolution
    // SAVE - sending data and saving features
    localparam IDLE = 2'd0;
    localparam CONV = 2'd1;
    localparam SAVE = 2'd2;
    logic [1:0] state, state_MRR, state_RM, state_mul_in = IDLE;
    logic [$clog2(F_RADIUS):0]     iter_counter, iter_counter_MRR, iter_counter_RM, iter_counter_acc;
    logic [$clog2(OUTPUT_DIM/2):0] outdim_counter, outdim_counter_mul_out, outdim_counter_compare, outdim_counter_acc;

    delay_module #(
        .N        ( $clog2(F_RADIUS)+1 ),
        .DELAY    ( 12                 )
    ) delay_counter (
        .clk   ( clk              ),
        .idata ( iter_counter     ),
        .odata ( iter_counter_acc )
    );

    delay_module #(
        .N        ( $clog2(OUTPUT_DIM/2)+1 ),
        .DELAY    ( 10                     )
    ) delay_out_counter (
        .clk   ( clk                    ),
        .idata ( outdim_counter         ),
        .odata ( outdim_counter_mul_out )
    );

    /////////////////////////////////////////////////////////////////
    //                        Handle MEMORY                        //
    /////////////////////////////////////////////////////////////////

    // Memory interface signals
    logic [AWIDTH-1:0] addra, addrb;
    logic [DWIDTH-1:0] dinb, douta, doutb;
    logic ena, ena_RM, web, enb, enb_RM;

    // State machine
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            iter_counter <= '0;
            outdim_counter <= '0;
        end else begin
            if (state == IDLE) begin
                event_reg.valid <= '0;
            end
            if (in_event.valid) begin
                iter_counter <= '0;
                outdim_counter <= '0;
                state <= CONV;
                event_reg <= in_event;
                event_reg.valid <= '0;
                edges_reg <= in_edges;
                features_reg <= in_features;
                edge_cnt_reg <= in_edge_cnt;
                num_iter <= ((in_edge_cnt+1) % 2) ? ((in_edge_cnt+2) / 2)-1 : ((in_edge_cnt+1) / 2)-1;
            end
            if (state == CONV) begin
                outdim_counter <= outdim_counter + 1;
                if (outdim_counter == ((OUTPUT_DIM/2)-1)) begin
                    if (iter_counter < num_iter) begin
                        iter_counter <= iter_counter + 1;
                        outdim_counter <= '0;
                    end
                    else begin
                        state <= SAVE;
                    end
                end
            end
            if (state == SAVE) begin
                state <= IDLE;
                event_reg.valid <= 1;
            end
            state_MRR <= state;
            state_RM <= state_MRR;
            state_mul_in <= state_RM;
            
            iter_counter_MRR <= iter_counter;
            iter_counter_RM <= iter_counter_MRR;
            ena_RM <= ena;
            enb_RM <= enb;
            
            outdim_counter_compare <= outdim_counter_mul_out;
            outdim_counter_acc <= outdim_counter_compare;
        end
    end

    logic [$clog2(MAX_EDGES) :0] idx_a, idx_a_RM;
    logic [$clog2(MAX_EDGES) :0] idx_b, idx_b_RM;

    assign idx_a = iter_counter_MRR != 0 ? ((iter_counter_MRR*2)-1) : 0;
    assign idx_b = iter_counter_MRR*2;

    // Context memory
    assign ena  = (state_MRR == CONV) && iter_counter_MRR != 0 && edges_reg[idx_a].is_connected;
    assign enb  = web || ((state_MRR == CONV) && edges_reg[idx_b].is_connected);
    assign dinb = memory_type'(features_reg);
    assign web  = state_MRR == SAVE;

    assign addra = (edges_reg[idx_a].df <= F_RADIUS) ? event_reg.f + edges_reg[idx_a].df*SKIP_STEP :
                                                                     event_reg.f - ((edges_reg[idx_a].df-F_RADIUS)*SKIP_STEP);
    assign addrb = (state_MRR == SAVE) ? event_reg.f : 
                   ((edges_reg[idx_b].df <= F_RADIUS) ? event_reg.f + edges_reg[idx_b].df*SKIP_STEP :
                                                                      event_reg.f - ((edges_reg[idx_b].df-F_RADIUS)*SKIP_STEP));

    always @(posedge clk) begin
        idx_a_RM <= idx_a;
        idx_b_RM <= idx_b;
    end

    memory #(
        .AWIDTH   ( AWIDTH  ),
        .DWIDTH   ( DWIDTH  ),
        .RAM_TYPE ( "block" )
    ) gen_memory (
        .clk      ( clk   ),
        .mem_ena  ( ena   ),    // READ only on PORTA
        .wea      ( '0    ),
        .addra    ( addra ),
        .dina     ( '0    ),
        .dinb     ( dinb  ),
        .douta    ( douta ),
        .mem_enb  ( enb   ),    // Write on last 
        .web      ( web   ),
        .addrb    ( addrb ),
        .doutb    ( doutb )
    );


    /////////////////////////////////////////////////////////////////
    //                      Quantize inputs                        //
    /////////////////////////////////////////////////////////////////

    logic [PRECISION_IN-1:0]   features_a_temp [INPUT_DIM-1:0];
    logic [PRECISION_IN-1:0]   features_b_temp [INPUT_DIM-1:0];
    logic [PRECISION_IN-1:0]   features_a [INPUT_DIM+1:0];
    logic [PRECISION_IN-1:0]   features_b [INPUT_DIM+1:0];

    genvar a, b;
    generate
        for (a = 0; a < INPUT_DIM; a++) begin : port_a_assign
            always @(posedge clk) begin
                features_a_temp[a][PRECISION_IN-1 : 0] = (iter_counter_RM != 0) ? {douta[((PRECISION_IN)*(a+1))-1 : (PRECISION_IN*a)]} :
                                                                                  features_reg[a];
                features_a[a] <= (ena_RM || (iter_counter_RM == 0)) ? features_a_temp[a] : '0;
            end
        end
        for (b = 0; b < INPUT_DIM; b++) begin : port_b_assign
            always @(posedge clk) begin
                features_b_temp[b][PRECISION_IN-1 : 0] = {doutb[((PRECISION_IN)*(b+1))-1 : (PRECISION_IN*b)]};
                features_b[b] <= enb_RM ? features_b_temp[b] : '0;
            end
        end       
    endgenerate

    logic signed [63:0] dt_expanded_a;
    logic signed [63:0] dt_expanded_b;
    logic signed [63:0] dt_scaled_a;
    logic signed [63:0] dt_scaled_b;
    assign dt_expanded_a = {{44{1'b0}},edges_reg[idx_a_RM].dt};
    assign dt_expanded_b = {{44{1'b0}},edges_reg[idx_b_RM].dt};
    assign dt_scaled_a = dt_expanded_a * MULTIPLIER_DIFF_T;
    assign dt_scaled_b = dt_expanded_b * MULTIPLIER_DIFF_T;

    // Changed for -1
    always @(posedge clk) begin
        features_a[2] <= (iter_counter_RM == 0) ? ZERO_POINT_IN : (ena_RM ? ((dt_scaled_a>>>32)+dt_scaled_a[31]+ZERO_POINT_IN) : '0);
        features_a[3] <= (iter_counter_RM == 0) ? ZERO_POINT_IN : (ena_RM ? (SCALE_IN[edges_reg[idx_a_RM].df]) : '0);
        features_b[2] <= enb_RM ? (dt_scaled_b>>>32)+dt_scaled_b[31]+ZERO_POINT_IN  : '0; //dif_t
        features_b[3] <= enb_RM ? SCALE_IN[edges_reg[idx_b_RM].df] : '0;
    end

   /////////////////////////////////////////////////////////////////
    //                   Perform multiplications                   //
    /////////////////////////////////////////////////////////////////

    //Prepare weights
    localparam WEIGHT_WIDTH = ((INPUT_DIM+2)*(PRECISION_OUT))+32; //bias
    logic [WEIGHT_WIDTH-1 : 0]     weight_mem1;
    logic [WEIGHT_WIDTH-1 : 0]     weight_mem2;
    logic [PRECISION_OUT-1:0] single_weight1_reg [INPUT_DIM+1:0];
    logic [31:0]            single_bias1_reg;
    logic [PRECISION_OUT-1:0] single_weight1 [INPUT_DIM+1:0];
    logic [31:0]            single_bias1;
    logic [PRECISION_OUT-1:0] single_weight2_reg [INPUT_DIM+1:0];
    logic [31:0]            single_bias2_reg;
    logic [PRECISION_OUT-1:0] single_weight2 [INPUT_DIM+1:0];
    logic [31:0]            single_bias2;

    dual_port_memory_weights #(
        .AWIDTH   ( $clog2(OUTPUT_DIM)               ),
        .DWIDTH   ( (PRECISION_OUT*(INPUT_DIM+2))+32 ),
        .STEP     ( 36                               ),
        .RAM_TYPE ( "block"                          ),
        .INIT_PATH ( INIT_PATH                       )
    ) weights_memory   (
        .clk      ( clk      ),
        .en       ( state == CONV   ),
        .addr     ( outdim_counter  ),
        .dout1    ( weight_mem1     ),
        .dout2    ( weight_mem2     )
    );

    genvar w;
    generate
        for (w = 0; w < INPUT_DIM+2; w++) begin : weights_assign
            always @(posedge clk) begin
                single_weight1_reg[w] <= weight_mem1[(((PRECISION_OUT)*(w+1))-1)+32 : ((PRECISION_OUT)*w)+32];
                single_weight2_reg[w] <= weight_mem2[(((PRECISION_OUT)*(w+1))-1)+32 : ((PRECISION_OUT)*w)+32];
            end
        end
    endgenerate

    always @(posedge clk) begin
        single_bias1_reg <= weight_mem1[31:0];
        single_bias2_reg <= weight_mem2[31:0];
        single_weight1 <= single_weight1_reg;
        single_bias1 <= single_bias1_reg;
        single_weight2 <= single_weight2_reg;
        single_bias2 <= single_bias2_reg;
    end

    logic [PRECISION_OUT-1:0] output_mat_a1;
    logic [PRECISION_OUT-1:0] output_mat_a2;
    logic [PRECISION_OUT-1:0] output_mat_b1;
    logic [PRECISION_OUT-1:0] output_mat_b2;
    logic [PRECISION_OUT-1:0] output_mat_a_full [OUTPUT_DIM-1:0];
    logic [PRECISION_OUT-1:0] output_mat_b_full [OUTPUT_DIM-1:0];
    logic [PRECISION_OUT-1:0] output_mat_full [OUTPUT_DIM-1:0];
    logic [PRECISION_OUT-1:0] output_features [OUTPUT_DIM-1:0];

    //Handle multiplications and outputs
    vec_mul_conv1 #(
        .INPUT_DIM         ( INPUT_DIM+2    ),
        .PRECISION_IN      ( PRECISION_IN   ),
        .PRECISION_OUT     ( PRECISION_OUT  )
    ) mul_a_1 (
        .clk               ( clk               ),
        .en                ( state_mul_in      ),
        .feature_vector    ( features_a        ),
        .weight_vector     ( single_weight1    ),
        .bias              ( single_bias1      ),
        .relu              ( 1'b1              ),
        .multiplier        ( MULTIPLIER_OUT    ),
        .zero_point_weight ( ZERO_POINT_WEIGHT ),
        .zero_point_out    ( ZERO_POINT_OUT    ),
        .result            ( output_mat_a1     )
    );

    vec_mul_conv1 #(
        .INPUT_DIM         ( INPUT_DIM+2    ),
        .PRECISION_IN      ( PRECISION_IN   ),
        .PRECISION_OUT     ( PRECISION_OUT  )
    ) mul_a_2 (
        .clk               ( clk               ),
        .en                ( state_mul_in      ),
        .feature_vector    ( features_a        ),
        .weight_vector     ( single_weight2    ),
        .bias              ( single_bias2      ),
        .relu              ( 1'b1              ),
        .multiplier        ( MULTIPLIER_OUT    ),
        .zero_point_weight ( ZERO_POINT_WEIGHT ),
        .zero_point_out    ( ZERO_POINT_OUT    ),
        .result            ( output_mat_a2     )
    );

    vec_mul_conv1 #(
        .INPUT_DIM         ( INPUT_DIM+2    ),
        .PRECISION_IN      ( PRECISION_IN   ),
        .PRECISION_OUT     ( PRECISION_OUT  )
    ) mul_b_1 (
        .clk               ( clk               ),
        .en                ( state_mul_in      ),
        .feature_vector    ( features_b        ),
        .weight_vector     ( single_weight1    ),
        .bias              ( single_bias1      ),
        .relu              ( 1'b1              ),
        .multiplier        ( MULTIPLIER_OUT    ),
        .zero_point_weight ( ZERO_POINT_WEIGHT ),
        .zero_point_out    ( ZERO_POINT_OUT    ),
        .result            ( output_mat_b1     )
    );

    vec_mul_conv1 #(
        .INPUT_DIM         ( INPUT_DIM+2    ),
        .PRECISION_IN      ( PRECISION_IN   ),
        .PRECISION_OUT     ( PRECISION_OUT  )
    ) mul_b_2 (
        .clk               ( clk               ),
        .en                ( state_mul_in      ),
        .feature_vector    ( features_b        ),
        .weight_vector     ( single_weight2    ),
        .bias              ( single_bias2      ),
        .relu              ( 1'b1              ),
        .multiplier        ( MULTIPLIER_OUT    ),
        .zero_point_weight ( ZERO_POINT_WEIGHT ),
        .zero_point_out    ( ZERO_POINT_OUT    ),
        .result            ( output_mat_b2     )
    );

    logic ena_mul_out, enb_mul_out;

    delay_module #(
        .N        ( 1   ),
        .DELAY    ( 9   )
    ) delay_ena (
        .clk   ( clk                            ),
        .idata ( ena || (iter_counter_MRR == 0) ),
        .odata ( ena_mul_out                    )
    );

    delay_module #(
        .N        ( 1  ),
        .DELAY    ( 9  )
    ) delay_enb (
        .clk   ( clk         ),
        .idata ( enb         ),
        .odata ( enb_mul_out )
    );

    always @(posedge clk) begin
        output_mat_a_full[outdim_counter_mul_out] <= ena_mul_out ? output_mat_a1 : '0;
        output_mat_a_full[outdim_counter_mul_out+36] <= ena_mul_out ? output_mat_a2 : '0;
        output_mat_b_full[outdim_counter_mul_out] <= enb_mul_out ? output_mat_b1 : '0;
        output_mat_b_full[outdim_counter_mul_out+36] <= enb_mul_out ? output_mat_b2 : '0;
    end

    always @(posedge clk) begin
        output_mat_full[outdim_counter_compare] <= output_mat_a_full[outdim_counter_compare] > output_mat_b_full[outdim_counter_compare] ? output_mat_a_full[outdim_counter_compare]
                                                                                                                                   : output_mat_b_full[outdim_counter_compare];
        output_mat_full[outdim_counter_compare+36] <= output_mat_a_full[outdim_counter_compare+36] > output_mat_b_full[outdim_counter_compare+36] ? output_mat_a_full[outdim_counter_compare+36]
                                                                                                                                   : output_mat_b_full[outdim_counter_compare+36];
        if (outdim_counter_acc == 0 && iter_counter_acc == 0) begin
            output_features <= '{default:ZERO_POINT_OUT};;
            output_features[outdim_counter_acc] <= output_mat_full[outdim_counter_acc];
            output_features[outdim_counter_acc+36] <= output_mat_full[outdim_counter_acc+36];
        end
        else begin
            output_features[outdim_counter_acc] <= output_features[outdim_counter_acc] > output_mat_full[outdim_counter_acc] ? output_features[outdim_counter_acc] : output_mat_full[outdim_counter_acc];
            output_features[outdim_counter_acc+36] <= output_features[outdim_counter_acc+36] > output_mat_full[outdim_counter_acc+36] ? output_features[outdim_counter_acc+36] : output_mat_full[outdim_counter_acc+36];
        end
        out_features <= output_features;
    end

    delay_module #(
        .N        ( 40 ),
        .DELAY    ( 12 )
    ) delay_event (
        .clk   ( clk     ),
        .idata ( {event_reg} ),
        .odata ( {out_event} )
    );

    delay_module #(
        .N        ( 441 ),
        .DELAY    ( 12  )
    ) delay_edge (
        .clk   ( clk     ),
        .idata ( {edges_reg} ),
        .odata ( {out_edges} )
    );

    delay_module #(
        .N        ( $clog2(MAX_EDGES)+1 ),
        .DELAY    ( 12                  )
    ) delay_edge_cnt (
        .clk   ( clk     ),
        .idata ( {edge_cnt_reg} ),
        .odata ( {out_edge_cnt} )
    );

    // synthesis translate_off
    always @(posedge clk) begin
        if (state != IDLE && in_event.valid) begin
            $display("DECREASE THE FIFO THROUGHPUT");
            $stop;
        end
    end
    // synthesis translate_on

endmodule

