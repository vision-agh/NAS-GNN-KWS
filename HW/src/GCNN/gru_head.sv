`timescale 1ns / 1ps

import nas_pkg::*;

module gru_head #(
    parameter int PRECISION            = 8,
    parameter int CLS_NUM              = 11,
    parameter int HEAD_DIM             = 72,
    parameter string INIT_PATH         = "C:/Users/wikto/NAS-GNN-KWS_OPT/HW/mem/head.mem"
)(
    input logic clk,
    input logic reset,
    input logic [PRECISION-1 :0]   in_features [HEAD_DIM-1 : 0],
    input logic in_valid,

    output logic                   out_valid,
    output logic [PRECISION-1 :0]  out_conf,
    output logic [PRECISION-1 :0]  out_cls [CLS_NUM-1:0]
);
                                    //   CONF | CLASS | GRU_X | LIN_2 | LIN_1 | GRU_H
//    logic [31:0]     multiplier [5:0] = {4943632,4791722,30244938,37899464,22171898,4709748};
//    logic [PRECISION-1:0]  zp_w [5:0] = {64,138,137,130,120,121};
//    logic [PRECISION-1:0]  zp_o [5:0] = {146,131,113,154,111,113};
    logic [31:0]     multiplier [5:0] = {3793016,3834090,22181600,20288056,16066800,1247868};
    logic [PRECISION-1:0]  zp_w [5:0] = {135,127,138,97,145,123};
    logic [PRECISION-1:0]  zp_o [5:0] = {160,121,129,55,73,129};
    localparam HIDDEN_IN_ZERO_POINT = 127;

    initial begin
        out_conf <= '{default:0};
        out_cls <= '{default:0};
    end

    localparam ITERATIONS = HEAD_DIM/2;
    localparam TAKEOFF = 3'd7;
    localparam GRU_H = 3'd0;
    localparam IDLE = 3'd1;
    localparam LINEAR_1 = 3'd2;
    localparam LINEAR_2 = 3'd3;
    localparam GRU_X = 3'd4;
    localparam PREPARE_HEAD = 3'd5;
    localparam CLS_HEAD = 3'd6;

    logic [2:0] state = TAKEOFF;
    logic [2:0] state_reg = TAKEOFF;
    logic [3:0] layer, layer_read, layer_in_mul = 0;
    logic en;
    logic en_read_w;
    logic en_in_mul;
    logic [9:0] counter, counter_select, counter_mul_out;

    logic [PRECISION-1:0] features [HEAD_DIM-1:0];
    logic [PRECISION-1:0] i_r [HEAD_DIM-1:0];
    logic [PRECISION-1:0] i_z [HEAD_DIM-1:0];
    logic [PRECISION-1:0] i_n [HEAD_DIM-1:0];
    logic [PRECISION-1:0] h_old [HEAD_DIM-1:0] = '{default: HIDDEN_IN_ZERO_POINT};
    logic [PRECISION-1:0] h_r [HEAD_DIM-1:0];
    logic [PRECISION-1:0] h_z [HEAD_DIM-1:0];
    logic [PRECISION-1:0] h_n [HEAD_DIM-1:0];
    logic [PRECISION-1:0] h_new [HEAD_DIM-1:0];

    logic [PRECISION-1:0] output1;
    logic [PRECISION-1:0] output2;
    logic [PRECISION-1:0] output1_reg;
    logic [PRECISION-1:0] output2_reg;
    logic [PRECISION-1:0] output_linear [HEAD_DIM-1:0];
    logic delay_one = 0;
    logic is_relu = 0;
    logic is_relu_read_w = 0;
    logic is_relu_mul = 0;
    logic new_h_done;
    logic i_r_ready = 0;
    logic i_z_ready = 0;
    logic i_n_ready = 0;

    // Control state machine
    always @(posedge clk) begin
        if (reset) begin
            state <= TAKEOFF;
            counter <= '0;
            en <= 0;
            en_read_w <= '0;
            en_in_mul <= '0;
            layer <= '0;
            is_relu <= 0;
            is_relu_read_w <= 0;
            is_relu_mul <= 0;
            delay_one <= 0;
            i_r_ready <= 0;
            i_z_ready <= 0;
            out_valid <= '0;
            i_n_ready <= 0;
        end else begin
            case(state)
                TAKEOFF: begin
                    en <= 1;
                    state <= GRU_H;
                    features <= '{default: HIDDEN_IN_ZERO_POINT};
                end
                GRU_H: begin
                    out_valid <= 0;
                    if (counter < ((HEAD_DIM*2)+ITERATIONS)-1) counter <= counter + 1;
                    if (counter == ITERATIONS-1) counter <= HEAD_DIM;
                    if (counter == ((HEAD_DIM)+ITERATIONS)-1) counter <= HEAD_DIM*2;                    
                    if (counter == ((HEAD_DIM*2)+ITERATIONS)-1) en <= 0;

                    if (counter_mul_out == HEAD_DIM) begin
                        h_r <= output_linear;
                    end
                    if (counter_mul_out == HEAD_DIM*2 ) begin
                        h_z <= output_linear;
                    end
                    if (counter_mul_out == ((HEAD_DIM*2)+ITERATIONS)-1) delay_one <= 1;
                    if (counter_mul_out == ((HEAD_DIM*2)+ITERATIONS-1) && delay_one) begin
                        state <= IDLE;
                        delay_one <= 0;
                        counter <= HEAD_DIM*3;
                        h_n <= output_linear;
                    end
                end
                IDLE: begin
                    if (in_valid) begin
                        state <= LINEAR_1;
                        en <= 1;
                        is_relu <= 1;
                        layer <= 1;
                        features <= in_features;
                    end
                end
                LINEAR_1: begin
                    if (counter < ((HEAD_DIM*3)+ITERATIONS)-1) counter <= counter + 1;
                    if (counter == ((HEAD_DIM*3)+ITERATIONS)-1) en <= 0;
                    if (counter_mul_out == ((HEAD_DIM*3)+ITERATIONS)-1) delay_one <= 1;
                    if ((counter_mul_out == ((HEAD_DIM*3)+ITERATIONS)-1) && delay_one) begin
                        delay_one <= 0;
                        counter <= HEAD_DIM*4;
                        state <= LINEAR_2;
                        en <= '1;
                        layer <= 2;
                        features <= output_linear;
                    end
                end
                LINEAR_2: begin
                    if (counter < ((HEAD_DIM*4)+ITERATIONS)-1) counter <= counter + 1;
                    if (counter == ((HEAD_DIM*4)+ITERATIONS)-1) en <= 0;
                    if (counter_mul_out == ((HEAD_DIM*4)+ITERATIONS)-1) delay_one <= 1;
                    if ((counter_mul_out == ((HEAD_DIM*4)+ITERATIONS)-1) && delay_one) begin
                        state <= GRU_X;
                        counter <= HEAD_DIM*5;
                        en <= '1;
                        layer <= 3;
                        delay_one <= 0;
                        is_relu <= 0;
                        features <= output_linear;
                    end
                end
                GRU_X: begin
                    if (counter < ((HEAD_DIM*7)+ITERATIONS)-1) counter <= counter + 1;
                    if (counter == ((HEAD_DIM*5)+ITERATIONS)-1) counter <= HEAD_DIM*6;
                    if (counter == ((HEAD_DIM*6)+ITERATIONS)-1) counter <= HEAD_DIM*7;                    
                    if (counter == ((HEAD_DIM*7)+ITERATIONS)-1) en <= 0;

                    if (counter_mul_out == HEAD_DIM*6) begin
                        i_r <= output_linear;
                        i_r_ready <= 1;
                    end
                    if (counter_mul_out == HEAD_DIM*7 ) begin
                        i_z <= output_linear;
                        i_z_ready <= 1;
                    end
                    if (counter_mul_out == ((HEAD_DIM*7)+ITERATIONS)-1) delay_one <= 1;
                    if (counter_mul_out == ((HEAD_DIM*7)+ITERATIONS)-1 && delay_one) begin
                        state <= PREPARE_HEAD;
                        delay_one <= 0;
                        i_n <= output_linear;
                        counter <= HEAD_DIM*8;
                        i_n_ready <= 1;
                    end
                end
                PREPARE_HEAD: begin
                    if (new_h_done) begin
                        i_n_ready <= 0;
                        i_z_ready <= 0;
                        i_r_ready <= 0;
                        state <= CLS_HEAD;
                        en <= '1;
                        layer <= 4;
                        features <= h_new;
                        h_old <= h_new;
                    end
                end
                CLS_HEAD: begin
                     if (counter < ((HEAD_DIM*8)+CLS_NUM)) counter <= counter + 1;
                     if (counter == ((HEAD_DIM*8)+CLS_NUM)-1) layer <= 5;
                     if (counter == ((HEAD_DIM*8)+CLS_NUM)) en <= 0;
                     if (counter_mul_out == ((HEAD_DIM*8)+CLS_NUM)) delay_one <= 1;
                     if (counter_mul_out == ((HEAD_DIM*8)+CLS_NUM) && delay_one) begin
                         state <= GRU_H;
                         counter <= '0;
                         delay_one <= '0;
                         out_cls <= output_linear[CLS_NUM-1:0];
                         out_conf <= output_linear[CLS_NUM];
                         out_valid <= 1;
                         en <= 1;
                         layer <= '0;
                     end
                 end
            endcase
            en_read_w <= en;
            en_in_mul <= en_read_w;
            layer_read <= layer;
            layer_in_mul <= layer_read;
            is_relu_read_w <= is_relu;
            is_relu_mul <= is_relu_read_w;
        end
    end

    assign counter_select = counter_mul_out % HEAD_DIM;

    /////////////////////////////////////////////////////////////////
    //                      Quantize inputs                        //
    /////////////////////////////////////////////////////////////////

    //Prepare weights
    localparam WEIGHT_DWIDTH = (HEAD_DIM*PRECISION)+32;
    localparam WEIGHT_AWIDTH = $clog2((HEAD_DIM*8)+CLS_NUM+1);
    logic [WEIGHT_DWIDTH-1 : 0] weight_mem1;
    logic [WEIGHT_DWIDTH-1 : 0] weight_mem2;
    logic [PRECISION-1:0]  single_weight1 [HEAD_DIM-1:0];
    logic [31:0]           single_bias1;
    logic [PRECISION-1:0]  single_weight2 [HEAD_DIM-1:0];
    logic [31:0]           single_bias2;

    delay_module #(
        .N        ( 10 ),
        .DELAY    ( 10 )
    ) delay_counter (
        .clk   ( clk             ),
        .idata ( counter         ),
        .odata ( counter_mul_out )
    );

    dual_port_memory_weights #(
        .AWIDTH   ( WEIGHT_AWIDTH  ),
        .DWIDTH   ( WEIGHT_DWIDTH  ),
        .STEP     ( 36             ),
        .RAM_TYPE ( "block"        ),
        .INIT_PATH ( INIT_PATH     )
    ) weights_memory   (
        .clk      ( clk             ),
        .en       ( state != IDLE   ),
        .addr     ( counter         ),
        .dout1    ( weight_mem1     ),
        .dout2    ( weight_mem2     )
    );

    genvar w;
    generate
        for (w = 0; w < HEAD_DIM; w++) begin : weights_assign
            always @(posedge clk) begin
                single_weight1[w] <= weight_mem1[(((PRECISION)*(w+1))-1)+32 : ((PRECISION)*w)+32];
                single_weight2[w] <= weight_mem2[(((PRECISION)*(w+1))-1)+32 : ((PRECISION)*w)+32];
            end
        end
    endgenerate

    always @(posedge clk) begin
        single_bias1 <= weight_mem1[31:0];
        single_bias2 <= weight_mem2[31:0];
    end

    //Handle multiplications and outputs
    vec_mul #(
        .INPUT_DIM         ( HEAD_DIM   ),
        .PRECISION_IN      ( PRECISION  ),
        .PRECISION_OUT     ( PRECISION  )
    ) mul_1 ( // Latency = 7
        .clk               ( clk                      ),
        .en                ( en_in_mul                ),
        .feature_vector    ( features                 ),
        .weight_vector     ( single_weight1           ),
        .bias              ( single_bias1             ),
        .relu              ( is_relu_mul              ),
        .multiplier        ( multiplier[layer_in_mul] ),
        .zero_point_weight ( zp_w[layer_in_mul]       ),
        .zero_point_out    ( zp_o[layer_in_mul]       ),
        .result            ( output1                  )
    );

    vec_mul #(
        .INPUT_DIM         ( HEAD_DIM   ),
        .PRECISION_IN      ( PRECISION  ),
        .PRECISION_OUT     ( PRECISION  )
    ) mul_2 (
        .clk               ( clk                      ),
        .en                ( en_in_mul                ),
        .feature_vector    ( features                 ),
        .weight_vector     ( single_weight2           ),
        .bias              ( single_bias2             ),
        .relu              ( is_relu_mul              ),
        .multiplier        ( multiplier[layer_in_mul] ),
        .zero_point_weight ( zp_w[layer_in_mul]       ),
        .zero_point_out    ( zp_o[layer_in_mul]       ),
        .result            ( output2                  )
    );


    always @(posedge clk) begin
        output1_reg <= output1;
        output2_reg <= output2;
        output_linear[counter_select] <= output1_reg;
        output_linear[counter_select+36] <= output2_reg;
        output_linear[counter_select] <= output1_reg;
        output_linear[counter_select+36] <= output2_reg;
    end

    //Hande R path
    logic [PRECISION-1:0] i_r_reg [HEAD_DIM-1:0];
    logic [PRECISION-1:0] h_r_reg [HEAD_DIM-1:0];
    logic [PRECISION:0] r_i_h [HEAD_DIM-1:0];
    logic [PRECISION-1:0] r_lut [HEAD_DIM-1:0];
    logic signed [PRECISION:0] r_lut_signed [HEAD_DIM-1:0];
    logic signed [PRECISION:0] h_n_signed [HEAD_DIM-1:0];

    logic i_r_ready_reg;
    logic i_r_ready_reg2;
    logic ready_hammard_r_hn;
    logic hammard_r_hn_valid;

    delay_module #(
        .N        ( 1 ),
        .DELAY    ( 4 )
    ) delay_read_r (
        .clk   ( clk           ),
        .idata ( i_r_ready     ),
        .odata ( i_r_ready_reg )
    );

    always @(posedge clk) begin
        ready_hammard_r_hn <= '0;
        i_r_ready_reg2 <= i_r_ready_reg;
        if (i_r_ready_reg == 1 && i_r_ready_reg2 == 0) begin
            ready_hammard_r_hn <= '1;
        end
    end

    genvar r;
    generate
        for (r = 0; r < HEAD_DIM; r++) begin : add_r_i_h
            always @(posedge clk) begin
                r_i_h[r] <= i_r_ready ? i_r_reg[r] + h_r_reg[r] : '0;
                i_r_reg[r] <= i_r_ready ? i_r[r] : '0;
                h_r_reg[r] <= i_r_ready ? h_r[r] : '0;
            end
            dist_mem_gen_0 lut_sigmoid_r (
                .clk    ( clk      ),
                .a      ( r_i_h[r] ),
                .qspo   ( r_lut[r] )
            );
            assign r_lut_signed[r] = {1'b0, r_lut[r]};
            assign h_n_signed[r] = {1'b0, h_n[r]};
        end
    endgenerate

    //Hande Z path
    logic [PRECISION-1:0] i_z_reg [HEAD_DIM-1:0];
    logic [PRECISION-1:0] h_z_reg [HEAD_DIM-1:0];
    logic [PRECISION:0] z_i_h [HEAD_DIM-1:0];
    logic [PRECISION-1:0] z_lut [HEAD_DIM-1:0];
    logic signed [PRECISION:0] z_to_mul [HEAD_DIM-1:0];
    logic signed [PRECISION:0] h_to_mul [HEAD_DIM-1:0];
    logic [PRECISION-1:0] z_diff [HEAD_DIM-1:0];
    logic signed [PRECISION:0] z_diff_to_mul [HEAD_DIM-1:0];

    logic i_z_ready_reg;
    logic i_z_ready_reg2;
    logic ready_hammard_z_h_old;
    logic hammard_z_h_old_valid;

    delay_module #(
        .N        ( 1 ),
        .DELAY    ( 4 )
    ) delay_read_z (
        .clk   ( clk           ),
        .idata ( i_z_ready     ),
        .odata ( i_z_ready_reg )
    );

    always @(posedge clk) begin
        ready_hammard_z_h_old <= '0;
        i_z_ready_reg2 <= i_z_ready_reg;
        if (i_z_ready_reg == 1 && i_z_ready_reg2 == 0) begin
            ready_hammard_z_h_old <= '1;
        end
    end

    genvar z;
    generate
        for (z = 0; z < HEAD_DIM; z++) begin : add_z_i_h
            always @(posedge clk) begin
                z_i_h[z] <= i_z_ready ? i_z_reg[z] + h_z_reg[z] : '0;
                i_z_reg[z]<= i_z_ready ? i_z[z] : '0;
                h_z_reg[z] <= i_z_ready ? h_z[z] : '0;
                z_diff[z] <= i_z_ready_reg2 ? (255-z_lut[z]) : '0;
            end
            dist_mem_gen_1 lut_sigmoid_z (
                .clk    ( clk      ),
                .a      ( z_i_h[z] ),
                .qspo   ( z_lut[z] )
            );
            assign z_to_mul[z] = {1'b0, z_lut[z]};
            assign h_to_mul[z] = {1'b0, h_old[z]};
            assign z_diff_to_mul[z] = {1'b0, z_diff[z]};
        end
    endgenerate

    //Hande N path
    logic [PRECISION-1:0] r_hn [HEAD_DIM-1:0];
    logic [PRECISION-1:0] i_n_reg [HEAD_DIM-1:0];
    logic [PRECISION-1:0] n_scaled [HEAD_DIM-1:0];
    logic [PRECISION:0] n_sum [HEAD_DIM-1:0];
    logic [PRECISION-1:0] n_lut [HEAD_DIM-1:0];
    logic [PRECISION-1:0] zh_mul [HEAD_DIM-1:0];
    logic [PRECISION-1:0] zn_mul [HEAD_DIM-1:0];

    logic signed [PRECISION:0] n_to_mul [HEAD_DIM-1:0];
    logic signed [PRECISION:0] zh_mul_signed [HEAD_DIM-1:0];
    logic signed [PRECISION:0] zn_mul_signed [HEAD_DIM-1:0];

    logic i_n_ready_reg;
    logic i_n_ready_reg2;
    logic ready_hammard_n_z_diff;
    logic hammard_n_z_diff_valid;
    logic ready_sum_vec;

    delay_module #(
        .N        ( 1  ),
        .DELAY    ( 11 )
    ) delay_read_n (
        .clk   ( clk           ),
        .idata ( i_n_ready     ),
        .odata ( i_n_ready_reg )
    );

    always @(posedge clk) begin
        ready_hammard_n_z_diff <= '0;
        i_n_ready_reg2 <= i_n_ready_reg;
        if (i_n_ready_reg == 1 && i_n_ready_reg2 == 0) begin
            ready_hammard_n_z_diff <= '1;
        end
        ready_sum_vec <= hammard_n_z_diff_valid;
    end

    genvar n;
    generate
        for (n = 0; n < HEAD_DIM; n++) begin : add_n_i_h
            always @(posedge clk) begin
                i_n_reg[n] <= i_n_ready ? i_n[n] : '0;
                n_sum[n] <= i_n_ready ? n_scaled[n] + r_hn[n] : '0;
                n_to_mul[n] <= i_n_ready ?  {1'b0, n_lut[n]} : '0;
                zh_mul_signed[n] <= i_n_ready ?  {1'b0, zh_mul[n]} : '0;
                zn_mul_signed[n] <= i_n_ready ?  {1'b0, zn_mul[n]} : '0;
            end
            dist_mem_gen_2 lut_n (
                .clk    ( clk         ),
                .a      ( i_n_reg[n]  ),
                .qspo   ( n_scaled[n] )
            );
            dist_mem_gen_3 lut_tanh_n (
                .clk    ( clk      ),
                .a      ( n_sum[n] ),
                .qspo   ( n_lut[n] )
            );
        end
    endgenerate

    hammard #(
        .DIM                ( HEAD_DIM  ),
        .PRECISION          ( PRECISION ),
        .MULTIPLIER         ( 16843010  ), //Scale r_hn (32 bit): 16843010
        .ZERO_POINT_IN_1    ( 0         ), //Output sigmoid r zero point: 0
        .ZERO_POINT_IN_2    ( 129       ), //Output linear zero point: 129
        .ZERO_POINT_OUT     ( 129       )  //Output r_hn zero point: 133
    ) mul_r_hn (
        .clk            ( clk                ),
        .reset          ( reset              ),
        .in_valid       ( ready_hammard_r_hn ),
        .vector_1       ( r_lut_signed       ),
        .vector_2       ( h_n_signed         ),
        .output_vector  ( r_hn               ),
        .out_valid      ( hammard_r_hn_valid )
    );

    hammard #(
        .DIM                ( HEAD_DIM  ),
        .PRECISION          ( PRECISION ),
        .MULTIPLIER         ( 17201276  ), //Scale z_h (32 bit): 17201276
        .ZERO_POINT_IN_1    ( 0         ), //Output sigmoid z zero point: 0
        .ZERO_POINT_IN_2    ( 127       ), //Hidden zero point: 127
        .ZERO_POINT_OUT     ( 127       )  //Output z_h zero point: 127
    ) mul_z_h_old (
        .clk            ( clk                   ),
        .reset          ( reset                 ),
        .in_valid       ( ready_hammard_z_h_old ),
        .vector_1       ( z_to_mul              ),
        .vector_2       ( h_to_mul              ),
        .output_vector  ( zh_mul                ),
        .out_valid      ( hammard_z_h_old_valid )
    );

    hammard #(
        .DIM                ( HEAD_DIM  ),
        .PRECISION          ( PRECISION ),
        .MULTIPLIER         ( 16876298  ), //Scale z_n (32 bit): 16876298
        .ZERO_POINT_IN_1    ( 127       ), //Output tanh n zero point: 127
        .ZERO_POINT_IN_2    ( 0         ), //Output sigmoid z zero point: 0
        .ZERO_POINT_OUT     ( 128       )  //Output z_n zero point: 128
    ) mul_diff_z_n (
        .clk            ( clk                    ),
        .reset          ( reset                  ),
        .in_valid       ( ready_hammard_n_z_diff ),
        .vector_1       ( n_to_mul               ),
        .vector_2       ( z_diff_to_mul          ),
        .output_vector  ( zn_mul                 ),
        .out_valid      ( hammard_n_z_diff_valid )
    );

    add_vectors_rescale #(
        .DIM                ( HEAD_DIM   ),
        .PRECISION          ( PRECISION  ),
        .MULTIPLIER_IN_1    ( 33'd4205512448 ), //Scale new_h_zh (32 bit): 4205512448
        .MULTIPLIER_IN_2    ( 33'd4203538432 ), //Scale new_h_zn (32 bit): 4203538432
        .ZERO_POINT_IN_1    ( 127        ), //Output z_h zero point: 127
        .ZERO_POINT_IN_2    ( 128        ), //Output z_n zero point: 128
        .ZERO_POINT_OUT     ( 127        )  //Hidden zero point: 127
    ) add_zn_zh (
        .clk                    ( clk ),
        .reset                  ( reset ),
        .in_valid               ( ready_sum_vec ),
        .input_vector_1         ( zh_mul_signed ),
        .input_vector_2         ( zn_mul_signed ),
        .output_vector          ( h_new ),
        .out_valid              ( new_h_done )
    );

    // synthesis translate_off
    always @(posedge clk) begin
        if (state != IDLE && in_valid) begin
            $display("GRU HEAD IS BROKEN - OVERFLOW!");
            $stop;
        end
    end
    // synthesis translate_on

endmodule