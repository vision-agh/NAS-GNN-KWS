`timescale 1ns / 1ps

import graph_pkg::*;

module convolution_reversed #(
    parameter int PRECISION_IN               = graph_pkg::PRECISION_CONV1,
    parameter int PRECISION_OUT              = graph_pkg::PRECISION_CONV1,
    parameter int INPUT_DIM                  = 2,
    parameter int OUTPUT_DIM                 = 64,
    parameter int MULTIPLIER_DIFF_T          = 214742,
    parameter int ZERO_POINT_IN              = 0,
    parameter int ZERO_POINT_OUT             = 135,
    parameter int MULTIPLIER_OUT             = 58670,
    parameter int ZERO_POINT_WEIGHT          = 30075,
    parameter string INIT_PATH               = "???",
    parameter logic [PRECISION_IN-1:0] SCALE_IN [21:0] = { 32767, 29490, 26214, 22937, 19660, 16383, 13107, 9830, 6553, 3277, 0, 65534,
                                                             62257, 58981, 55704, 52427, 49150, 45874, 42597, 39320, 36044, 32767 }
)(
    input logic clk,
    input logic reset,
    input event_type                   in_event,
    input edge_type  [MAX_EDGES-1:0]   in_edges,
    input logic [PRECISION_IN-1 :0]    in_features [INPUT_DIM-1 : 0],

    output event_type                  out_event,
    output edge_type  [MAX_EDGES-1:0]  out_edges,
    output logic [PRECISION_OUT-1 :0]  out_features [OUTPUT_DIM-1 : 0]
);

    logic [$clog2(F_RADIUS):0] counter, counter_reg, counter_read;
    logic [$clog2(F_RADIUS):0] counter_quant, counter_mul_out, counter_compare, counter_acc;
    logic [$clog2(OUTPUT_DIM/2):0] outdim_counter, outdim_counter_reg, outdim_counter_mul_out, outdim_counter_compare, outdim_counter_acc;

    event_type in_event_reg; // fifo output
    edge_type[MAX_EDGES-1:0] in_edges_reg;
    event_type out_event_reg; // fifo output
    edge_type[MAX_EDGES-1:0] out_edges_reg;
    typedef logic [PRECISION_IN-1 :0] features_type [INPUT_DIM-1 : 0];
    typedef logic [(PRECISION_IN*INPUT_DIM)-1 :0] memory_type;
    features_type in_features_reg;

    localparam IDLE = 2'd0;
    localparam CONV = 2'd1;
    
    localparam AWIDTH = $clog2(NUM_CHANNEL);
    localparam DWIDTH = INPUT_DIM * PRECISION_IN;
    logic state = IDLE;
    logic state_reg = IDLE;
    logic state_read = IDLE;
    logic state_quant = IDLE;

    initial begin
        out_event_reg <= '{default:0};
        out_edges_reg <= '{default:0};
        in_edges_reg <= '{default:0};
        in_event_reg <= '{default:0};
    end

    /////////////////////////////////////////////////////////////////
    //                        Handle MEMORY                        //
    /////////////////////////////////////////////////////////////////

    // Memory interface signals
    logic [AWIDTH-1:0] addra, addrb;
    logic [DWIDTH-1:0] dinb, douta, doutb;
    logic ena, wea, web, enb, ena_reg, enb_reg, web_reg, ena_mul_out, enb_mul_out;

    // Context memory instantiation
    memory #(
        .AWIDTH   ( AWIDTH  ),
        .DWIDTH   ( DWIDTH  ),
        .RAM_TYPE ( "block" )
    ) gen_memory (
        .clk      ( clk   ),
        .mem_ena  ( ena   ),    // READ only on PORTA
        .wea      ( wea   ),
        .addra    ( addra ),
        .dina     ( '0    ),
        .dinb     ( dinb  ),
        .douta    ( douta ),
        .mem_enb  ( enb   ),    // Write on last 
        .web      ( web   ),
        .addrb    ( addrb ),
        .doutb    ( doutb )
    );

    logic condition_a, condition_b, condition_a_reg, condition_b_reg;
    edge_type [MAX_EDGES-1:0] edges_reg;

    assign ena  = (counter_reg <= F_RADIUS && condition_a && state_reg==CONV) ? 1'b1 : 1'b0;
    assign enb  = (counter_reg <= F_RADIUS && condition_b && state_reg==CONV) ? 1'b1 : web;
    assign wea  = 0;
    assign dinb = memory_type'(in_features_reg);
    assign web  = (counter_reg == F_RADIUS) && state_reg==CONV;// && outdim_counter_reg==0;

    assign addra = in_event_reg.f + counter_reg*SKIP_STEP;
    assign addrb = in_event_reg.f - 100 + (counter_reg*SKIP_STEP);

    assign condition_a = in_edges_reg[counter_reg].is_connected;
    assign condition_b = (counter_reg < F_RADIUS) ? in_edges_reg[F_RADIUS+1+counter_reg].is_connected : 1'b0;
    logic start;

    // Counter and edge processing
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            start <= '0;
            ena_reg <= '0;
            enb_reg <= '0;
            web_reg <= '0;
            counter <= F_RADIUS;
            outdim_counter <= OUTPUT_DIM/2;
        end else begin
            if (state == CONV) begin
                counter <= counter + 1;
            end
            if (counter == F_RADIUS && state==CONV && outdim_counter < (OUTPUT_DIM/2)-1) begin
                outdim_counter <= outdim_counter + 1;
                counter <= '0;
            end
            if (in_event.valid) begin
                counter <= '0;
                outdim_counter <= '0;
                state <= CONV;
                in_event_reg <= in_event;
                in_edges_reg <= in_edges;
                in_features_reg <= in_features;
            end
            if (counter == F_RADIUS && state == CONV && outdim_counter == (OUTPUT_DIM/2)-1 && outdim_counter_reg == (OUTPUT_DIM/2)-1) begin
                state <= IDLE;
                start <= '1;
            end
            if (state == IDLE) begin
                if (start == 1) begin
                    out_edges_reg <= in_edges_reg;
                    out_event_reg <= in_event_reg;
                    start <= '0;
                end
                else begin
                    out_event_reg.valid <= '0;
                end
            end
            enb_reg <= enb;
            ena_reg <= ena;
            web_reg <= web;

            state_reg <= state;
            state_read <= state_reg;
            state_quant <= state_read;
            
            outdim_counter_reg <= outdim_counter;
            outdim_counter_compare <= outdim_counter_mul_out;
            outdim_counter_acc <= outdim_counter_compare;

            counter_reg <= counter;
            counter_read <= counter_reg;
            counter_quant <= counter_read;
            counter_compare <= counter_mul_out;
            counter_acc <= counter_compare;
        end
    end

    delay_module #(
        .N        ( $clog2(OUTPUT_DIM/2)+1 ),
        .DELAY    ( 10                     )
    ) delay_counter_dim (
        .clk   ( clk                    ),
        .idata ( outdim_counter         ),
        .odata ( outdim_counter_mul_out )
    );

    delay_module #(
        .N        ( 1 ),
        .DELAY    ( 9 )
    ) delay_ena (
        .clk   ( clk         ),
        .idata ( ena         ),
        .odata ( ena_mul_out )
    );

    delay_module #(
        .N        ( 1        ),
        .DELAY    ( 9        )
    ) delay_enb (
        .clk   ( clk         ),
        .idata ( enb         ),
        .odata ( enb_mul_out )
    );

    delay_module #(
        .N        ( $clog2(F_RADIUS)+1 ),
        .DELAY    ( 10                     )
    ) delay_counter (
        .clk   ( clk             ),
        .idata ( counter         ),
        .odata ( counter_mul_out )
    );


    /////////////////////////////////////////////////////////////////
    //                      Quantize inputs                        //
    /////////////////////////////////////////////////////////////////

    logic [PRECISION_IN-1:0] features_a_temp [INPUT_DIM-1:0];
    logic [PRECISION_IN-1:0] features_b_temp [INPUT_DIM-1:0];
    logic [PRECISION_IN-1:0] features_a [INPUT_DIM+1:0];
    logic [PRECISION_IN-1:0] features_b [INPUT_DIM+1:0];

    genvar a, b;
    generate
        for (a = 0; a < INPUT_DIM; a++) begin : port_a_assign
            always @(posedge clk) begin
                features_a_temp[a][PRECISION_IN-1 : 0] = {douta[((PRECISION_IN)*(a+1))-1 : (PRECISION_IN*a)]};
                features_a[a] <= ena_reg ? features_a_temp[a] : '0;
            end
        end
        for (b = 0; b < INPUT_DIM; b++) begin : port_b_assign
            always @(posedge clk) begin
                features_b_temp[b][PRECISION_IN-1 : 0] = !web_reg ? {doutb[((PRECISION_IN)*(b+1))-1 : (PRECISION_IN*b)]}
                                                               : in_features_reg[b];
                features_b[b] <= enb_reg ? features_b_temp[b] : '0;
            end
        end       
    endgenerate

    logic signed [63:0] dt_expanded_a;
    logic signed [63:0] dt_expanded_b;
    logic signed [63:0] dt_scaled_a;
    logic signed [63:0] dt_scaled_b;
    assign dt_expanded_a = {{44{1'b0}},in_edges_reg[counter_read].dt};
    assign dt_expanded_b = {{44{1'b0}},in_edges_reg[F_RADIUS+1+counter_read].dt};
    assign dt_scaled_a = dt_expanded_a * MULTIPLIER_DIFF_T;
    assign dt_scaled_b = dt_expanded_b * MULTIPLIER_DIFF_T;

    always @(posedge clk) begin
        features_a[INPUT_DIM] <= ena_reg ? ZERO_POINT_IN-(dt_scaled_a>>>32)-dt_scaled_a[31] : '0; //dif_t
        features_a[INPUT_DIM+1] <= ena_reg ? SCALE_IN[counter_read] : '0;
        features_b[INPUT_DIM] <= (enb_reg && counter_read < F_RADIUS) ? ZERO_POINT_IN-(dt_scaled_b>>>32)-dt_scaled_b[31]  : ZERO_POINT_IN; //dif_t
        features_b[INPUT_DIM+1] <= (enb_reg) ? SCALE_IN[F_RADIUS+1+counter_read] : '0;
    end

    /////////////////////////////////////////////////////////////////
    //                   Perform multiplications                   //
    /////////////////////////////////////////////////////////////////

    //Prepare weights
    typedef logic [71 :0] weights_reg_type [8 : 0];
    typedef logic [647 :0] weights_wire_type;
    logic [71 : 0]  weight_mem1;
    logic [71 : 0]  weight_mem2;
    weights_reg_type single_weight1_reg;
    weights_reg_type single_weight2_reg;
    weights_wire_type single_weight1_wire;
    weights_wire_type single_weight2_wire;

    logic [PRECISION_OUT-1:0] prepare_weight1 [INPUT_DIM+1:0];
    logic [31:0]              prepare_bias1;
    logic [PRECISION_OUT-1:0] prepare_weight2 [INPUT_DIM+1:0];
    logic [31:0]              prepare_bias2;

    logic [PRECISION_OUT-1:0] single_weight1 [INPUT_DIM+1:0];
    logic [31:0]              single_bias1;
    logic [PRECISION_OUT-1:0] single_weight2 [INPUT_DIM+1:0];
    logic [31:0]              single_bias2;

    localparam WEIGHT_ADDR = ((INPUT_DIM/9)+1)*OUTPUT_DIM;
    localparam WEIGHT_DATA = 72;
    logic [$clog2(WEIGHT_ADDR) : 0] weight_counter, weight_counter_reg;
    logic                           weight_en, weight_en_reg, weight_en_reg2, weight_en_reg3;
    logic                           load_first, load_weights, load_weights_reg;
    assign load_weights_reg = (counter == F_RADIUS && state==CONV) || in_event.valid;

     always @(posedge clk) begin
        if (reset) begin
            load_first <= 1;
            weight_counter <= '0;
            weight_en <= '0;
        end
        else begin
            if (load_first || (load_weights && state==CONV)) begin
                weight_en <= 1'b1;
                load_first <= 1'b0;
            end
            if (weight_en) begin
                weight_counter <= weight_counter+1;
                if (weight_counter == WEIGHT_ADDR/2-1) begin
                    weight_counter <= '0;
                end
            end
            if ((weight_counter+1) % 9 == 0) begin
                weight_en <= 1'b0;
            end
        end
    end

    delay_module #(
        .N        ( 1 ),
        .DELAY    ( 2 )
    ) delay_load (
        .clk   ( clk     ),
        .idata ( load_weights_reg ),
        .odata ( load_weights     )
    );

    dual_port_memory_weights #(
        .AWIDTH   ( $clog2(WEIGHT_ADDR) ),
        .DWIDTH   ( WEIGHT_DATA         ),
        .STEP     ( WEIGHT_ADDR/2       ),
        .RAM_TYPE ( "block"             ),
        .INIT_PATH ( INIT_PATH          )
    ) weights_memory   (
        .clk      ( clk             ),
        .en       ( weight_en       ),
        .addr     ( weight_counter  ),
        .dout1    ( weight_mem1     ),
        .dout2    ( weight_mem2     )
    );

    genvar w;
    generate
        for (w = 0; w < INPUT_DIM; w++) begin : weights_assign
            always @(posedge clk) begin
                if (weight_en_reg2) begin
                    prepare_weight1[w+2] <= single_weight1_wire[((w+1)*8)+71 : (w*8)+72];
                    prepare_weight2[w+2] <= single_weight2_wire[((w+1)*8)+71 : (w*8)+72];
                end
            end
        end
    endgenerate

    assign single_weight1_wire = weights_wire_type'(single_weight1_reg);
    assign single_weight2_wire =  weights_wire_type'(single_weight2_reg);

    always @(posedge clk) begin
        weight_counter_reg <= weight_counter % 9;
        weight_en_reg <= weight_en;
        weight_en_reg2 <= weight_en_reg;
        weight_en_reg3 <= weight_en_reg2;
        if (weight_en_reg) begin
            single_weight1_reg[8-weight_counter_reg] <= weight_mem1;
            single_weight2_reg[8-weight_counter_reg] <= weight_mem2;
        end
        if (weight_en_reg2) begin
            prepare_bias1 <= single_weight1_wire[31:0];
            prepare_bias2 <= single_weight2_wire[31:0];
            prepare_weight1[0] <= single_weight1_wire[39:32];
            prepare_weight2[0] <= single_weight2_wire[39:32];
            prepare_weight1[1] <= single_weight1_wire[47:40];
            prepare_weight2[1] <= single_weight2_wire[47:40];
        end
        if (weight_en_reg3 && !weight_en_reg2) begin
            single_weight1 <= prepare_weight1;
            single_weight2 <= prepare_weight2;
            single_bias1 <= prepare_bias1;
            single_bias2 <= prepare_bias2;
        end
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
    vec_mul #(
        .INPUT_DIM         ( INPUT_DIM+2    ),
        .PRECISION_IN      ( PRECISION_IN   ),
        .PRECISION_OUT     ( PRECISION_OUT  )
    ) mul_a_1 (
        .clk               ( clk               ),
        .en                ( state_quant       ),
        .feature_vector    ( features_a        ),
        .weight_vector     ( single_weight1    ),
        .bias              ( single_bias1      ),
        .relu              ( 1'b1              ),
        .multiplier        ( MULTIPLIER_OUT    ),
        .zero_point_weight ( ZERO_POINT_WEIGHT ),
        .zero_point_out    ( ZERO_POINT_OUT    ),
        .result            ( output_mat_a1     )
    );

    vec_mul #(
        .INPUT_DIM         ( INPUT_DIM+2    ),
        .PRECISION_IN      ( PRECISION_IN   ),
        .PRECISION_OUT     ( PRECISION_OUT  )
    ) mul_a_2 (
        .clk               ( clk               ),
        .en                ( state_quant       ),
        .feature_vector    ( features_a        ),
        .weight_vector     ( single_weight2    ),
        .bias              ( single_bias2      ),
        .relu              ( 1'b1              ),
        .multiplier        ( MULTIPLIER_OUT    ),
        .zero_point_weight ( ZERO_POINT_WEIGHT ),
        .zero_point_out    ( ZERO_POINT_OUT    ),
        .result            ( output_mat_a2     )
    );

    vec_mul #(
        .INPUT_DIM         ( INPUT_DIM+2    ),
        .PRECISION_IN      ( PRECISION_IN   ),
        .PRECISION_OUT     ( PRECISION_OUT  )
    ) mul_b_1 (
        .clk               ( clk               ),
        .en                ( state_quant       ),
        .feature_vector    ( features_b        ),
        .weight_vector     ( single_weight1    ),
        .bias              ( single_bias1      ),
        .relu              ( 1'b1              ),
        .multiplier        ( MULTIPLIER_OUT    ),
        .zero_point_weight ( ZERO_POINT_WEIGHT ),
        .zero_point_out    ( ZERO_POINT_OUT    ),
        .result            ( output_mat_b1     )
    );

    vec_mul #(
        .INPUT_DIM         ( INPUT_DIM+2    ),
        .PRECISION_IN      ( PRECISION_IN   ),
        .PRECISION_OUT     ( PRECISION_OUT  )
    ) mul_b_2 (
        .clk               ( clk               ),
        .en                ( state_quant       ),
        .feature_vector    ( features_b        ),
        .weight_vector     ( single_weight2    ),
        .bias              ( single_bias2      ),
        .relu              ( 1'b1              ),
        .multiplier        ( MULTIPLIER_OUT    ),
        .zero_point_weight ( ZERO_POINT_WEIGHT ),
        .zero_point_out    ( ZERO_POINT_OUT    ),
        .result            ( output_mat_b2     )
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

        if (outdim_counter_acc == 0 && counter_acc == 0) begin
            output_features <= '{default:'0};
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
        .N        ( 32 ),
        .DELAY    ( 12  )
    ) delay_event (
        .clk   ( clk     ),
        .idata ( {out_event_reg} ),
        .odata ( {out_event}     )
    );

    delay_module #(
        .N        ( 441 ),
        .DELAY    ( 12   )
    ) delay_edge (
        .clk   ( clk     ),
        .idata ( {out_edges_reg} ),
        .odata ( {out_edges}     )
    );

    // synthesis translate_off
    always @(posedge clk) begin
        if (state_reg != IDLE && in_event.valid) begin
            $display("DECREASE THE FIFO THROUGHPUT");
            $stop;
        end
    end
    // synthesis translate_on

endmodule