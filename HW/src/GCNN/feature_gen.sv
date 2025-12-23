`timescale 1ns / 1ps

import nas_pkg::*;

module feature_gen #(
    parameter T_MULTIPLIER = GEN_MULTIPLIER_T,    
    parameter [63:0] F_MULTIPLIER = GEN_MULTIPLIER_F,  
    parameter ZERO_POINT   = GEN_ZERO_POINT    
                            
)(
    input logic                      clk,
    input logic                      reset,
    input event_type                 in_event,
    input edge_type   [MAX_EDGES-1:0] in_edges,

    output event_type                         out_event,
    output edge_type  [MAX_EDGES-1:0]         out_edges,
    output logic      [PRECISION_GEN-1:0]     t_feature,
    output logic      [PRECISION_GEN-1:0]     f_feature
);
    logic [7 : 0]                       num_edges;
    logic [$clog2(MAX_EDGES)-1 : 0]     counter,counter_reg;
    logic [23 : 0] t_temp;
    logic [15 : 0] f_temp;

    logic [F_WIDTH-1:0] edge_f; 
    logic [T_WIDTH-1:0] edge_t;
    logic fin;
    logic dividend_tvalid,divisor_tvalid;
    
    assign edge_t = in_event.t - in_edges[counter].dt;
    assign edge_f = (counter <= 10) ? in_event.f + counter*SKIP_STEP : in_event.f + (counter - MAX_EDGES)*SKIP_STEP ;

    assign out_event.t = in_event.t;
    assign out_event.f = in_event.f;
    // assign out_event.is_last = in_event.is_last;
    assign out_event.valid = f_avg_valid && t_avg_valid;
    assign out_edges = in_edges;
    
    always @(posedge clk) begin
        if (reset) begin
            num_edges <= '0; 
            counter   <= MAX_EDGES-1;
            t_temp    <= '0;
            f_temp    <= '0;
            counter_reg <= '0;
            fin       <= 0;
            divisor_tvalid <= 0;
            dividend_tvalid <= 0;
        end else begin
            counter_reg <= counter;

            if (in_event.valid) begin
                num_edges <= '0;
                counter   <= '0;
                t_temp    <= '0;
                f_temp    <= '0;
                fin       <=  0;
                divisor_tvalid <= 0;
                dividend_tvalid <= 0;
            end else begin
                if(counter == MAX_EDGES-1) begin
                    counter <= counter;
                end else begin
                    counter <= counter + 1;
                end
                
                if(counter_reg == MAX_EDGES-2 && counter == MAX_EDGES-1) begin
                    fin <= 1;
                    divisor_tvalid <= 1;
                    dividend_tvalid <= 1;
                end else begin
                    fin <= fin;
                    divisor_tvalid  <= 0;
                    dividend_tvalid <= 0;
                end
                
                if(in_edges[counter].is_connected && !fin) begin
                    num_edges <= num_edges + 1;
                    t_temp  <= t_temp + edge_t;
                    f_temp  <= f_temp + edge_f;
                end else begin
                    num_edges <= num_edges;
                    t_temp  <= t_temp;
                    f_temp  <= f_temp;
                end 
            end
        end
    end
    
    logic [31 : 0] t_average;
    logic [15 : 0] f_average;
    logic [63:0] round_t_average,extended_t_average;
    logic [63:0] round_f_average,extended_f_average;

    assign round_t_average =  {{(34){1'b0} }, t_average[31:2]};
    assign round_f_average =  {{(50){1'b0} }, f_average[15:2]};
    
    assign extended_t_average = num_edges != 0 ? (round_t_average+t_average[1]) * T_MULTIPLIER : '0;
    assign extended_f_average = num_edges != 0 ? (round_f_average+f_average[1]) * F_MULTIPLIER : '0;

    assign t_feature = (extended_t_average>>>32) + extended_t_average[31] + ZERO_POINT;
    assign f_feature = (extended_f_average>>>32) + extended_f_average[31] + ZERO_POINT;

    div_t div_t ( //32 clock latency
        .aclk                   ( clk             ),
        .s_axis_divisor_tdata   ( num_edges       ),//8 bit
        .s_axis_divisor_tvalid  ( divisor_tvalid  ),
        .s_axis_dividend_tdata  ( t_temp          ),//24 bit
        .s_axis_dividend_tvalid ( dividend_tvalid ),
        .m_axis_dout_tdata      ( t_average       ),//32
        .m_axis_dout_tvalid     ( t_avg_valid     )
    );

    div_f div_f (//32 clock latency
        .aclk                   ( clk             ),
        .s_axis_divisor_tdata   ( num_edges       ),//8 bit
        .s_axis_divisor_tvalid  ( divisor_tvalid  ),
        .s_axis_dividend_tdata  ( f_temp          ),//16 bit
        .s_axis_dividend_tvalid ( dividend_tvalid ),
        .m_axis_dout_tdata      ( f_average       ),//16
        .m_axis_dout_tvalid     ( f_avg_valid     )
    );

endmodule
