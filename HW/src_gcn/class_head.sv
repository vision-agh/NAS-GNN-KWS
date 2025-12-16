`timescale 1ns / 1ps

import graph_pkg::*;

module class_head #(
    parameter int PRECISION            = 8,
    parameter int CLS_NUM              = 20,
    parameter int HEAD_DIM             = 72,
    parameter string INIT_PATH         = "/home/pwz/Repo/gcnn-audio-fpga/HW/mem/head.mem"
)(
    input logic clk,
    input logic reset,
    input logic [PRECISION-1 :0]   in_features [HEAD_DIM-1 : 0],
    input logic in_valid,

    output logic                   out_valid,
    output logic [PRECISION-1 :0]  out_cls [CLS_NUM-1:0]
);
                                    //   CONF | CLASS | GRU_X | LIN_2 | LIN_1 | GRU_H
    logic [31:0]     multiplier [1:0] = {14189199, 1817144};
    logic [PRECISION-1:0]  zp_w [1:0] = {157, 131};
    logic [PRECISION-1:0]  zp_o [1:0] = {147, 117};

    initial begin
        out_conf <= '{default:0};
        out_cls <= '{default:0};
    end

    localparam ITERATIONS = HEAD_DIM/2;
    localparam IDLE = 3'd0;
    localparam LINEAR_1 = 3'd1;
    localparam CLS_HEAD = 3'd2;

    logic [1:0] state = IDLE;
    logic [1:0] state_reg = IDLE;
    logic [3:0] layer, layer_read, layer_in_mul = 0;
    logic en;
    logic en_read_w;
    logic en_in_mul;
    logic [9:0] counter, counter_select, counter_mul_out;

    logic [PRECISION-1:0] features [HEAD_DIM-1:0];

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
            state <= IDLE;
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
                IDLE: begin
                    if (in_valid) begin
                        state <= LINEAR_1;
                        en <= 1;
                        is_relu <= 1;
                        layer <= 0;
                        out_valid <= 0;
                        features <= in_features;
                    end
                end
                LINEAR_1: begin
                    if (counter < (ITERATIONS)-1) counter <= counter + 1;
                    if (counter == (ITERATIONS)-1) en <= 0;
                    if (counter_mul_out == (ITERATIONS)-1) delay_one <= 1;
                    if ((counter_mul_out == (ITERATIONS)-1) && delay_one) begin
                        delay_one <= 0;
                        counter <= HEAD_DIM;
                        state <= LINEAR_2;
                        en <= '1;
                        is_relu <= 0;
                        layer <= 1;
                        features <= output_linear;
                    end
                end
                CLS_HEAD: begin
                     if (counter < ((HEAD_DIM)+CLS_NUM)) counter <= counter + 1;
                     if (counter == ((HEAD_DIM)+CLS_NUM)-1) layer <= 5;
                     if (counter == ((HEAD_DIM)+CLS_NUM)) en <= 0;
                     if (counter_mul_out == ((HEAD_DIM)+CLS_NUM-1)) delay_one <= 1;
                     if (counter_mul_out == ((HEAD_DIM)+CLS_NUM-1) && delay_one) begin
                         state <= IDLE;
                         counter <= '0;
                         out_cls <= output_linear[CLS_NUM-1:0];
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
        output_linear[counter_select+32] <= output2_reg;
        output_linear[counter_select] <= output1_reg;
        output_linear[counter_select+32] <= output2_reg;
    end

    // synthesis translate_off
    always @(posedge clk) begin
        if (state != IDLE && in_valid) begin
            $display("GRU HEAD IS BROKEN - OVERFLOW!");
            $stop;
        end
    end
    // synthesis translate_on

endmodule