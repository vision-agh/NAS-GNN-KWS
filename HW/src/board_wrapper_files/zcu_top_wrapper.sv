`timescale 1ns / 1ps
import nas_pkg::*;

module zcu_top_wrapper (
    input  logic CLK_IN1_D_0_clk_p,
    input  logic CLK_IN1_D_0_clk_n,
    input  logic rst_ext_0,
    input  logic i2s_bclk_0,
    input  logic i2s_d_in_0,
    input  logic i2s_lr_0,
    output logic out_valid,
    output logic [PRECISION_GEN-1:0] out_conf,
    output logic [(PRECISION_GEN * CLS_NUM)-1:0] out_cls
);

    logic clk_200;
    logic clk_48;

    clk_wiz_zcu clk_wiz_zcu_i (
        .clk_in1_p  (CLK_IN1_D_0_clk_p),
        .clk_in1_n (CLK_IN1_D_0_clk_n),
        .reset    (rst_ext_0),
        .clk_out1 (clk_48),
        .clk_out2 (clk_200)
    );

    NAS_KWS_TOP u_nas_kws_top (
        .clk_48    (clk_48),
        .clk_200   (clk_200),
        .rst_ext   (rst_ext_0),
        .i2s_bclk  (i2s_bclk_0),
        .i2s_d_in  (i2s_d_in_0),
        .i2s_lr    (i2s_lr_0),
        .out_valid (out_valid),
        .out_conf  (out_conf),
        .out_cls   (out_cls)
    );

endmodule