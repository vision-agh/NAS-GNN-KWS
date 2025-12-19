`timescale 1ns / 1ps

import nas_pkg::*;

module NAS_GCNN_TOP(

    input  logic        clock_125p,
    input  logic        clock_125n,
    input  logic        rst_ext,

    // I2S signals from codec
    input  logic        i2s_bclk, 
    input  logic        i2s_d_in,
    input  logic        i2s_lr,

    // GCNN outputs
    output logic        out_valid,
    output logic [PRECISION_GEN-1 :0] out_conf,
    output logic [(8*20)-1 :0]        out_cls
);


    logic [6:0] aer_data;
    logic       aer_req;
    logic       aer_ack;

    logic [T_WIDTH-1:0] gcnn_t;
    logic [F_WIDTH-1:0] gcnn_f;
    logic                   gcnn_valid;

    logic clk_48;
    logic clk_200;
    
    // (* MARK_DEBUG="true" *) logic [(8*20)-1 :0]        out_cls;
    // (* MARK_DEBUG="true" *) logic [PRECISION_GEN-1 :0] out_conf;
    // (* MARK_DEBUG="true" *) logic        out_valid;
    
    
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


    NAS_GCNN_bridge #(
        .T_WIDTH      (T_WIDTH),
        .F_WIDTH      (F_WIDTH)
    ) i_bridge (
        .clock_200    (clk_200),
        .clock_48     (clk_48),
        .rst_ext      (rst_ext),
        // AER I/F
        .AER_DATA_OUT (aer_data),
        .AER_REQ      (aer_req),
        .AER_ACK      (aer_ack),
        // GCNN I/F
        .t            (gcnn_t),
        .f            (gcnn_f),
        .is_valid     (gcnn_valid)
    );

    top i_GCNN (
        .clk        (clk_200),
        .reset      (rst_ext),
        .t          (gcnn_t),
        .f          (gcnn_f),
        .is_valid   (gcnn_valid),
        
        // Outputs
        .out_valid  (out_valid),
        .out_conf   (out_conf),
        .out_cls    (out_cls)
    );
    
    clk_wiz_0 u_clock_gen (
          .clk_out1  (clk_48),
          .clk_out2  (clk_200),
          .reset    (rst_ext),
          .clk_in1_p (clock_125p),
          .clk_in1_n (clock_125n)
      );
      
endmodule