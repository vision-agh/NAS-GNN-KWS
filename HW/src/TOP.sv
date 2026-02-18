`timescale 1ns / 1ps

import nas_pkg::*;

module NAS_KWS_TOP ( 
    input  logic        clk_48,
    input  logic        clk_200,
    input  logic        rst_ext,

    // I2S signals from codec
    input  logic        i2s_bclk, 
    input  logic        i2s_d_in,
    input  logic        i2s_lr,

    // GCNN outputs
    output logic                   out_valid,
    output logic [PRECISION_GEN-1:0] out_conf,
    output logic [(PRECISION_GEN*CLS_NUM)-1:0]        out_cls
);

    logic [6:0] aer_data;
    logic       aer_req;
    logic       aer_ack;

    logic [T_WIDTH-1:0] link_t;
    logic [15:0] idx_time_link;
    logic [F_WIDTH-1:0] link_f;
    logic               link_valid;
    

    // 48 MHZ domain
    OpenNas_Cascade_MONO_64ch i_NAS (
        .clock_48     (clk_48),
        .rst_ext      (rst_ext),
        // I2S Bus
        .i2s_bclk     (i2s_bclk),
        .i2s_d_in     (i2s_d_in),
        .i2s_lr       (i2s_lr),
        // AER Output
        .AER_DATA_OUT (aer_data),
        .AER_REQ      (aer_req),
        .AER_ACK      (aer_ack)
    );

    // 48 MHZ domain
    timestamp_gen #(  
        .T_WIDTH(T_WIDTH), 
        .F_WIDTH(F_WIDTH)
    ) u_ts_gen (
        .clk       (clk_48),
        .rst       (rst_ext),
        // AER Interface
        .AER_DATA  (aer_data),
        .AER_REQ   (aer_req),
        .AER_ACK   (aer_ack),
        // Output to KWS
        .out_t     (link_t),
        .out_f     (link_f),
        .out_valid (link_valid),
        .idx_time (idx_time_link)
    );

    KWS #(
        .T_WIDTH       (T_WIDTH),
        .F_WIDTH       (F_WIDTH),
        .NUM_CHANNEL   (NUM_CHANNEL),
        .PRECISION_GEN (PRECISION_GEN),
        .WEIGHT        (WEIGHT),
        .DECAY_SHIFT   (DECAY_SHIFT),
        .CLS_NUM   (CLS_NUM)
    ) u_kws (
        .clock_200 (clk_200),
        .clock_48  (clk_48),
        .rst_ext   (rst_ext),
        
        .in_t      (link_t),
        .in_f      (link_f),
        .in_valid  (link_valid),
        .idx_time  (idx_time_link),
        
        .cnn_valid (out_valid),
        .cnn_conf  (out_conf),
        .cnn_class (out_cls)
    );

endmodule