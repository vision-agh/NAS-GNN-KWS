`timescale 1ns / 1ps
import nas_pkg::*;

module ok_top_wrapper (
    input  logic clk_200_p,
    input  logic clk_200_n,
    input  logic i2s_bclk,
    input  logic i2s_d_in,
    input  logic i2s_lr,
//    output logic out_valid,
    output logic [PRECISION_GEN-1:0] out_conf
//    output logic [(PRECISION_GEN * CLS_NUM)-1:0] out_cls
);

    logic clk_200;
    logic clk_48;
    logic [15:0] rst_shift = 16'hFFFF; 
    logic sys_rst;
    
    
    always_ff @(posedge clk_48) begin
        rst_shift <= {rst_shift[14:0], 1'b0};
    end
    
    assign sys_rst = rst_shift[15];
    
    clk_wiz_ok clk_wiz_ok_i (
        .clk_in1_p (clk_200_p),
        .clk_in1_n (clk_200_n),
        .clk_out1  (clk_48),
        .clk_out2  (clk_200)
    );

    NAS_KWS_TOP u_nas_kws_top (
        .clk_48    (clk_48),
        .clk_200   (clk_200),
        .rst_ext   (sys_rst),
        .i2s_bclk  (i2s_bclk),
        .i2s_d_in  (i2s_d_in),
        .i2s_lr    (i2s_lr),
        .out_valid (out_valid),
        .out_conf  (out_conf),
        .out_cls   (out_cls)
    );

endmodule