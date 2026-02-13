`timescale 1ns / 1ps

import nas_pkg::*;

module convolution_sparse #(
    parameter int PRECISION_IN               = nas_pkg::PRECISION_CONV1,
    parameter int PRECISION_OUT              = nas_pkg::PRECISION_CONV1,
    parameter int INPUT_DIM                  = 2,
    parameter int MEMORY_FACTOR              = 8,
    parameter int OUTPUT_DIM                 = 64,
    parameter int MULTIPLIER_DIFF_T          = 214742,
    parameter int ZERO_POINT_IN              = 0,
    parameter int ZERO_POINT_OUT             = 129,
    parameter int MULTIPLIER_OUT             = 58670,
    parameter int ZERO_POINT_WEIGHT          = 30075,
    parameter string INIT_PATH_W             = "???",
    parameter string INIT_PATH_B             = "???",
    parameter logic [PRECISION_IN-1:0] SCALE_IN [20:0] = { 29490, 26214, 22937, 19660, 16383, 13107, 9830, 6553, 3277, 0, 65534,
                                                             62257, 58981, 55704, 52427, 49150, 45874, 42597, 39320, 36044, 32767 }
)(
    input logic clk,
    input logic reset,
    input event_type                   in_event,
    output logic                       in_ready,
    input edge_type  [MAX_EDGES-1:0]   in_edges,
    input logic [PRECISION_IN-1 :0]    in_features [INPUT_DIM-1 : 0],
    input logic [$clog2(MAX_EDGES) :0] in_edge_cnt,

    output event_type                   out_event,
    output edge_type  [MAX_EDGES-1:0]   out_edges,
    output logic [PRECISION_OUT-1 :0]   out_features [OUTPUT_DIM-1 : 0],
    output logic [$clog2(MAX_EDGES) :0] out_edge_cnt
);

    typedef logic [PRECISION_IN-1 :0] features_type [INPUT_DIM-1 : 0];
    typedef logic [(PRECISION_IN*(INPUT_DIM/MEMORY_FACTOR))-1 :0] memory_type;
    localparam AWIDTH = $clog2(NUM_CHANNEL*MEMORY_FACTOR);
    localparam DWIDTH = (INPUT_DIM/MEMORY_FACTOR) * PRECISION_IN;

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
    features_type                     features_read;
    features_type                     features_read_a;
    features_type                     features_read_b;

    // STATE MACHINE:
    // IDLE - wait
    // CONV - convolution
    // SAVE - sending data and saving features
    localparam IDLE = 2'd0;
    localparam LOAD = 2'd1;
    localparam CONV = 2'd2;
    localparam SAVE = 2'd3;
    logic [1:0] state, state_reg, state_RM, state_mul_in = IDLE;
    logic [$clog2(F_RADIUS):0]                     iter_counter, iter_counter_reg;
    logic [$clog2((OUTPUT_DIM*MEMORY_FACTOR)/2):0] outdim_counter, outdim_counter_reg;

    /////////////////////////////////////////////////////////////////
    //                        Handle MEMORY                        //
    /////////////////////////////////////////////////////////////////

    // Memory interface signals

    logic                          get_feature;
    logic                          save_feature;
    logic [$clog2(NUM_CHANNEL): 0] ref_addr;
    logic                          feature_done;
    logic [PRECISION_IN-1:0] features_a [INPUT_DIM+1:0];
    logic [PRECISION_IN-1:0] features_b [INPUT_DIM+1:0];
    logic [PRECISION_IN-1:0] features_a_reg [INPUT_DIM+1:0];
    logic [PRECISION_IN-1:0] features_b_reg [INPUT_DIM+1:0];
    logic [$clog2(MAX_EDGES)-1 : 0] ptr_mem;
    logic en_mula, en_mulb, en_mula_next, en_mulb_next, en_mula_reg, en_mulb_reg;
    logic [PRECISION_IN-1:0] pos_a [1:0];
    logic [PRECISION_IN-1:0] pos_b [1:0];

    logic signed [63:0] dt_expanded;
    logic signed [63:0] dt_scaled;
    assign dt_expanded = {{44{1'b0}},edges_reg[ptr_mem].dt};
    assign dt_scaled = dt_expanded * MULTIPLIER_DIFF_T;

    // State machine for FEATURES
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            iter_counter <= '0;
            outdim_counter <= '0;
            get_feature <= '0;
            save_feature <= '0;
            ref_addr <= '0;
            ptr_mem <= 0;
            en_mula <= '0;
            en_mulb <= '0;
            en_mula_next <= '0;
            en_mulb_next <= '0;
            event_reg <= '{default:0};
            edges_reg <= '{default:0};
            features_reg <= '{default:0};
            edge_cnt_reg <= '{default:0};
        end else begin
        
            // Wait for event, cache input
            if (state == IDLE) begin
                event_reg.valid <= '0;
                in_ready <= '1;
            end
            if (in_event.valid) begin
                iter_counter <= '0;
                in_ready <= '0;
                outdim_counter <= '0;
                state <= LOAD;
                ptr_mem <= 0;
                event_reg <= in_event;
                event_reg.valid <= '0;
                edges_reg <= in_edges;
                features_reg <= in_features;
                edge_cnt_reg <= in_edge_cnt;
                num_iter <= ((in_edge_cnt+1) % 2) ? ((in_edge_cnt+2) / 2)-1 : ((in_edge_cnt+1) / 2)-1;
            end
            
            // Load first feature
            if (state == LOAD) begin
                get_feature <= 1'b0;
                features_a[71:0] <= features_reg;
                features_a[72] <= ZERO_POINT_IN;
                features_a[73] <= ZERO_POINT_IN;
                if (state_reg == IDLE) begin
                    if (edges_reg[0].is_connected) begin
                        get_feature <= 1'b1;
                        ref_addr <= (edges_reg[0].df <= F_RADIUS) ? event_reg.f + edges_reg[0].df*SKIP_STEP :
                                                                    event_reg.f - ((edges_reg[0].df-F_RADIUS)*SKIP_STEP);
                    end
                    else begin
                        state <= CONV;
                        en_mula <= '1;
                        ptr_mem <= 1;
                        en_mulb <= '0;
                    end
                end
                if (feature_done) begin
                    state <= CONV;
                    en_mula <= '1;
                    ptr_mem <= 1;
                    features_b[71:0] <= features_read;
                    features_b[72] <= ((dt_scaled>>>32)+dt_scaled[31]+ZERO_POINT_IN);
                    features_b[73] <= (SCALE_IN[edges_reg[ptr_mem].df]);
                    en_mulb <= '1;
                end
            end
            
            // Perform convolution
            if (state == CONV) begin
                get_feature <= 1'b0;
                outdim_counter <= outdim_counter + 1;
                if (outdim_counter == (OUTPUT_DIM-1)) begin
                    if (iter_counter < num_iter) begin
                        iter_counter <= iter_counter + 1;
                        outdim_counter <= '0;
                        features_a[71:0] <= features_read_a;
                        features_b[71:0] <= features_read_b;
                        features_a[72] <= pos_a[0];
                        features_b[72] <= pos_b[0];
                        features_a[73] <= pos_a[1];
                        features_b[73] <= pos_b[1];
                        en_mula <= en_mula_next;
                        en_mulb <= en_mulb_next;
                        en_mulb_next <= 0;
                        en_mula_next <= 0;
                    end
                    else begin
                        state <= SAVE;
                    end
                end
                if (outdim_counter == 2 || outdim_counter == 22) begin
                    if (edges_reg[ptr_mem].is_connected) begin
                        get_feature <= 1'b1;
                        ref_addr <= (edges_reg[ptr_mem].df <= F_RADIUS) ? event_reg.f + edges_reg[ptr_mem].df*SKIP_STEP :
                                                                          event_reg.f - ((edges_reg[ptr_mem].df-F_RADIUS)*SKIP_STEP);                     
                    end
                    else begin
                        ptr_mem <= ptr_mem + 1;
                    end
                end
                if (feature_done) begin
                    ptr_mem <= ptr_mem + 1;
                    if (ptr_mem % 2 == 0) begin
                        features_read_b <= features_read;
                        pos_b[0] <= ((dt_scaled>>>32)+dt_scaled[31]+ZERO_POINT_IN);
                        pos_b[1] <= (SCALE_IN[edges_reg[ptr_mem].df]);
                        en_mulb_next <= 1;
                    end
                    else begin
                        features_read_a <= features_read;
                        pos_a[0] <= ((dt_scaled>>>32)+dt_scaled[31]+ZERO_POINT_IN);
                        pos_a[1] <= (SCALE_IN[edges_reg[ptr_mem].df]);
                        en_mula_next <= 1;
                    end
                end                
            end

            // Save last feature
            if (state == SAVE) begin
                en_mula <= '0;
                en_mulb <= '0;
                save_feature <= 1'b0;
                ptr_mem <= 1;
                if (state_reg == CONV) begin
                    save_feature <= 1'b1;
                    ref_addr <= event_reg.f;
                end
                if ( feature_done ) begin
                    state <= IDLE;
                    event_reg.valid <= 1;
                end                
            end

            features_a_reg <= features_a;
            features_b_reg <= features_b;
            en_mula_reg <= en_mula;
            en_mulb_reg <= en_mulb;
            state_reg <= state;            
            iter_counter_reg <= iter_counter;
            outdim_counter_reg <= outdim_counter;
        end
    end

    handle_memory #() handle_memory (
        .clk           ( clk           ),
        .reset         ( reset         ),
        .get_feature   ( get_feature   ),
        .save_feature  ( save_feature  ),
        .ref_addr      ( ref_addr      ),
        .in_feature    ( features_reg  ),
        .out_feature   ( features_read ),
        .feature_done  ( feature_done  )
    );

    // State machine for WEIGHTS
    localparam WEIGHT_WIDTH = 36*8; //bias
    logic [WEIGHT_WIDTH-1 : 0]  weight_mem1;
    logic [WEIGHT_WIDTH-1 : 0]  weight_mem2;
    logic [35 : 0]              bias_mem1;
    logic [35 : 0]              bias_mem2;
    logic [PRECISION_OUT-1:0]   single_weight [INPUT_DIM+1:0];
    logic [31:0]                single_bias;

    dual_port_memory_weights #(
        .AWIDTH   ( $clog2(OUTPUT_DIM*2) ),
        .DWIDTH   ( WEIGHT_WIDTH         ),
        .STEP     ( 72                   ),
        .RAM_TYPE ( "block"              ),
        .INIT_PATH ( INIT_PATH_W         )
    ) weights_memory   (
        .clk      ( clk      ),
        .en       ( state == CONV   ),
        .addr     ( outdim_counter  ),
        .dout1    ( weight_mem1     ),
        .dout2    ( weight_mem2     )
    );

    dual_port_memory_weights #(
        .AWIDTH   ( $clog2(OUTPUT_DIM*2) ),
        .DWIDTH   ( 36                   ),
        .STEP     ( 72                   ),
        .RAM_TYPE ( "block"              ),
        .INIT_PATH ( INIT_PATH_B         )
    ) bias_memory (
        .clk      ( clk      ),
        .en       ( state == CONV   ),
        .addr     ( outdim_counter  ),
        .dout1    ( bias_mem1       ),
        .dout2    ( bias_mem2       )
    );


    genvar w;
    generate
        for (w = 0; w < INPUT_DIM/2; w++) begin : weights_assign
            assign single_weight[w] = weight_mem1[(((PRECISION_OUT)*(w+1))-1) : ((PRECISION_OUT)*w)];
            assign single_weight[w+36] = weight_mem2[(((PRECISION_OUT)*(w+1))-1) : ((PRECISION_OUT)*w)];
        end
    endgenerate
    assign single_weight[72] = bias_mem1[7:0];
    assign single_weight[73] = bias_mem1[15:8];
    assign single_bias = bias_mem2[31:0];

    // Multiplication (on reg
    logic [PRECISION_OUT-1:0] output_mat_a;
    logic [PRECISION_OUT-1:0] output_mat_b;
    logic [PRECISION_OUT-1:0] output_mat_a_full [OUTPUT_DIM-1:0];
    logic [PRECISION_OUT-1:0] output_mat_b_full [OUTPUT_DIM-1:0];
    logic [PRECISION_OUT-1:0] output_mat_full [OUTPUT_DIM-1:0];

    vec_mul #(
        .INPUT_DIM         ( INPUT_DIM+2    ),
        .PRECISION_IN      ( PRECISION_IN   ),
        .PRECISION_OUT     ( PRECISION_OUT  )
    ) mul_a (
        .clk               ( clk               ),
        .en                ( en_mula_reg       ),
        .feature_vector    ( features_a_reg    ),
        .weight_vector     ( single_weight     ),
        .bias              ( single_bias       ),
        .relu              ( 1'b1              ),
        .multiplier        ( MULTIPLIER_OUT    ),
        .zero_point_weight ( ZERO_POINT_WEIGHT ),
        .zero_point_out    ( ZERO_POINT_OUT    ),
        .result            ( output_mat_a      )
    );

    vec_mul #(
        .INPUT_DIM         ( INPUT_DIM+2    ),
        .PRECISION_IN      ( PRECISION_IN   ),
        .PRECISION_OUT     ( PRECISION_OUT  )
    ) mul_b (
        .clk               ( clk               ),
        .en                ( en_mulb_reg       ),
        .feature_vector    ( features_b_reg    ),
        .weight_vector     ( single_weight     ),
        .bias              ( single_bias       ),
        .relu              ( 1'b1              ),
        .multiplier        ( MULTIPLIER_OUT    ),
        .zero_point_weight ( ZERO_POINT_WEIGHT ),
        .zero_point_out    ( ZERO_POINT_OUT    ),
        .result            ( output_mat_b      )
    );

    // Post Process
    logic en_mula_out, en_mulb_out;
    logic [$clog2((OUTPUT_DIM*MEMORY_FACTOR)/2):0] outdim_counter_mul_out, outdim_counter_compare, outdim_counter_acc;
    logic [PRECISION_OUT-1:0] output_features [OUTPUT_DIM-1:0];
    logic [$clog2(F_RADIUS):0] iter_counter_acc;

    delay_module #(
        .N        ( 2   ),
        .DELAY    ( 8   )
    ) delay_en (
        .clk   ( clk                        ),
        .idata ( {en_mula, en_mulb}         ),
        .odata ( {en_mula_out, en_mulb_out} )
    );

    delay_module #(
        .N        ( $clog2((OUTPUT_DIM*MEMORY_FACTOR)/2)+1 ),
        .DELAY    ( 8                                      )
    ) delay_outdim (
        .clk   ( clk         ),
        .idata ( outdim_counter         ),
        .odata ( outdim_counter_mul_out )
    );

    delay_module #(
        .N        ( $clog2(F_RADIUS)+1 ),
        .DELAY    ( 8                  )
    ) delay_iter (
        .clk   ( clk              ),
        .idata ( iter_counter     ),
        .odata ( iter_counter_acc )
    );

    always @(posedge clk) begin
        output_mat_a_full[outdim_counter_mul_out] <= en_mula_out ? output_mat_a : '0;
        output_mat_b_full[outdim_counter_mul_out] <= en_mulb_out ? output_mat_b : '0;
    end

    always @(posedge clk) begin
        outdim_counter_compare <= outdim_counter_mul_out;
        outdim_counter_acc <= outdim_counter_compare;
        output_mat_full[outdim_counter_compare] <= output_mat_a_full[outdim_counter_compare] > output_mat_b_full[outdim_counter_compare] ?
                                                   output_mat_a_full[outdim_counter_compare] : output_mat_b_full[outdim_counter_compare]; 
        if (outdim_counter_acc == 0 && iter_counter_acc == 0) begin
            output_features <= '{default:ZERO_POINT_OUT};;
            output_features[outdim_counter_acc] <= output_mat_full[outdim_counter_acc];
        end
        else begin
            output_features[outdim_counter_acc] <= output_features[outdim_counter_acc] > output_mat_full[outdim_counter_acc] ? output_features[outdim_counter_acc] : output_mat_full[outdim_counter_acc];
        end
        out_features <= output_features;
    end

    delay_module #(
        .N        ( 41 ),
        .DELAY    ( 5 )
    ) delay_event (
        .clk   ( clk         ),
        .idata ( {event_reg} ),
        .odata ( {out_event} )
    );

    delay_module #(
        .N        ( 441 ),
        .DELAY    ( 5   )
    ) delay_edge (
        .clk   ( clk     ),
        .idata ( {edges_reg} ),
        .odata ( {out_edges} )
    );

    delay_module #(
        .N        ( $clog2(MAX_EDGES)+1 ),
        .DELAY    ( 5                   )
    ) delay_edge_cnt (
        .clk   ( clk     ),
        .idata ( {edge_cnt_reg} ),
        .odata ( {out_edge_cnt} )
    );

    // synthesis translate_off
    always @(posedge clk) begin
        if (!in_ready && in_event.valid) begin
            $display("DECREASE THE FIFO THROUGHPUT");
            $stop;
        end
    end
    // synthesis translate_on


endmodule