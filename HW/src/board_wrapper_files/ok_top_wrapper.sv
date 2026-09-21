// `timescale 1ns / 1ps

// import nas_pkg::*;

// module ok_top_wrapper (
//     input  wire [4:0]   okUH,
//     output wire [2:0]   okHU,
//     inout  wire [31:0]  okUHU,
//     inout  wire         okAA,
    
//     input  logic clk_200_p,
//     input  logic clk_200_n,
//     input  logic i2s_bclk,
//     input  logic i2s_d_in,
//     input  logic i2s_lr
// );

//     logic clk_200;
//     logic clk_48;
//     logic out_valid;
//     logic [PRECISION_GEN-1:0] out_conf;
//     logic [(PRECISION_GEN * CLS_NUM)-1:0] out_cls;
    
//     wire [31:0] ep00wire;
//     wire [31:0] ep01wire;
    
//     wire        epA0read;
//     wire [31:0] epA0data;
    
//     wire okClk;
    
//     logic [7:0] valid_cnt;

//     // --- REVERTED: Back to simple asynchronous routing ---
//     wire rst = ep00wire[0];
//     wire capture_enable = ep01wire[0];

//     always_ff @(posedge clk_200) begin
//         if (rst) begin
//             valid_cnt <= 8'h00;
//         end else if (out_valid) begin
//             valid_cnt <= valid_cnt + 1'b1;
//         end
//     end

//     frontpanel_0 okHI (
//         .okUH(okUH),
//         .okHU(okHU),
//         .okUHU(okUHU),
//         .okAA(okAA),
//         .okClk(okClk),
//         .wi00_ep_dataout(ep00wire),
//         .wi01_ep_dataout(ep01wire),
//         .poa0_ep_datain(epA0data),
//         .poa0_ep_read(epA0read)
//     );

//     wire fifo_full;
//     wire fifo_empty;

//     fifo_generator_frontpanel u_fifo (
//         .wr_clk(clk_200),
//         .wr_rst(rst),   // Reverted to single reset
//         .rd_clk(okClk),
//         .rd_rst(rst),   // Reverted to single reset
//         .din({24'd0, valid_cnt, out_cls, out_conf}),
//         .wr_en(out_valid & capture_enable), // Reverted to raw capture enable
//         .rd_en(epA0read),
//         .dout(epA0data),
//         .full(fifo_full),
//         .empty(fifo_empty)
//     );
    
//     clk_wiz_ok clk_wiz_ok_i (
//         .clk_in1_p (clk_200_p),
//         .clk_in1_n (clk_200_n),
//         .clk_out1  (clk_48),
//         .clk_out2  (clk_200)
//     );

//     NAS_KWS_TOP u_nas_kws_top (
//         .clk_48    (clk_48),
//         .clk_200   (clk_200),
//         .rst_ext   (rst), // Reverted to raw reset
//         .i2s_bclk  (i2s_bclk),
//         .i2s_d_in  (i2s_d_in),
//         .i2s_lr    (i2s_lr),
//         .out_valid (out_valid),
//         .out_conf  (out_conf),
//         .out_cls   (out_cls)
//     );

// endmodule
`timescale 1ns / 1ps

import nas_pkg::*;

module ok_top_wrapper (
    input  wire [4:0]   okUH,
    output wire [2:0]   okHU,
    inout  wire [31:0]  okUHU,
    inout  wire         okAA,
    
    input  logic clk_200_p,
    input  logic clk_200_n,
    input  logic i2s_bclk,
    input  logic i2s_d_in,
    input  logic i2s_lr
);

    logic clk_200;
    logic clk_48;
    logic rst;
    logic out_valid;
    logic [PRECISION_GEN-1:0] out_conf;
    logic [(PRECISION_GEN * CLS_NUM)-1:0] out_cls;
    
    wire [31:0] ep00wire;
    wire [31:0] ep01wire;
    
    wire        epA0read;
    wire [31:0] epA0data;
    
    wire okClk;
    
    logic [7:0] valid_cnt;

    always_ff @(posedge clk_200) begin
        if (rst) begin
            valid_cnt <= 8'h00;
        end else if (out_valid) begin
            valid_cnt <= valid_cnt + 1'b1;
        end
    end

    frontpanel_0 okHI (
        .okUH(okUH),
        .okHU(okHU),
        .okUHU(okUHU),
        .okAA(okAA),
        .okClk(okClk),
        
        .wi00_ep_dataout(ep00wire),
        .wi01_ep_dataout(ep01wire),
        
        .poa0_ep_datain(epA0data),
        .poa0_ep_read(epA0read)
    );
    
    assign rst = ep00wire[0];
    wire capture_enable = ep01wire[0];

    wire fifo_full;
    wire fifo_empty;

    fifo_generator_0 u_fifo (
        .wr_clk(clk_200),
        .wr_rst(rst),
        .rd_clk(okClk),
        .rd_rst(rst),
        .din({24'd0, valid_cnt, out_cls, out_conf}),
        .wr_en(out_valid & capture_enable),
        .rd_en(epA0read),
        .dout(epA0data),
        .full(fifo_full),
        .empty(fifo_empty)
    );
    
    clk_wiz_ok clk_wiz_ok_i (
        .clk_in1_p (clk_200_p),
        .clk_in1_n (clk_200_n),
        .clk_out1  (clk_48),
        .clk_out2  (clk_200)
    );

    NAS_KWS_TOP u_nas_kws_top (
        .clk_48    (clk_48),
        .clk_200   (clk_200),
        .rst_ext   (rst),
        .i2s_bclk  (i2s_bclk),
        .i2s_d_in  (i2s_d_in),
        .i2s_lr    (i2s_lr),
        .out_valid (out_valid),
        .out_conf  (out_conf),
        .out_cls   (out_cls)
    );

endmodule