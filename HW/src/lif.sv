`timescale 1ns / 1ps
import nas_pkg::*;

module lif #(
    parameter int T_WIDTH     = 32,
    parameter int F_WIDTH     = 7,
    parameter int NUM_CHANNEL = 128,
    parameter int WEIGHT      = 32,
    parameter int DECAY_SHIFT = 8
)(
    input  logic                clk,
    input  logic                rst,
    
    input  logic                in_req,
    input  logic [T_WIDTH-1:0]  in_t,
    input  logic [F_WIDTH:0]    in_f,
    
    input  logic [15:0]         idx_time_in,

    output logic                out_valid,
    output logic [T_WIDTH-1:0]  out_t,
    output logic [F_WIDTH-1:0]  out_f,
    output logic                out_p,

    output logic [T_WIDTH-1:0]  last_time_out,
    output logic [15:0]         idx_time_out
);

    localparam int DATA_WIDTH = T_WIDTH + 32;
    localparam int ADDR_WIDTH = $clog2(NUM_CHANNEL);

    logic v1, v2, v3;
    logic [T_WIDTH-1:0] t1, t2, t3;
    logic [F_WIDTH-1:0] f1, f2, f3;
    logic               p1, p2, p3;

    logic [DATA_WIDTH-1:0] mem_dout_a;
    logic [DATA_WIDTH-1:0] mem_din_b;
    logic mem_we_b;

    logic [31:0] calc_pot_result;
    logic        calc_fire;
    
    logic [15:0] prev_idx_time;
    logic [T_WIDTH-1:0] current_window_last_ts;
    logic               event_seen_in_window;

    // ----------------------------------------------------------------------
    // Main Pipeline
    // ----------------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            v1 <= 0; v2 <= 0; v3 <= 0;
            t1 <= '0; t2 <= '0; t3 <= '0;
            f1 <= '0; f2 <= '0; f3 <= '0;
            p1 <= '0; p2 <= '0; p3 <= '0;
            out_valid <= 0;
        end else begin
            v1 <= in_req;
            t1 <= in_t;
            f1 <= in_f[F_WIDTH-1:0];
            p1 <= in_f[F_WIDTH];

            v2 <= v1;
            t2 <= t1;
            f2 <= f1;
            p2 <= p1;

            v3 <= v2;
            t3 <= t2;
            f3 <= f2;
            p3 <= p2;
            
            out_valid <= v3 && calc_fire;
            out_t     <= t3;
            out_f     <= f3;
            out_p     <= p3;
        end
    end

    // ----------------------------------------------------------------------
    // LIF Mathematics
    // ----------------------------------------------------------------------
    logic [T_WIDTH-1:0] last_time;
    logic [31:0]        last_pot;
    logic [T_WIDTH-1:0] delta_t;
    logic [31:0]        decay;
    logic [31:0]        pot_decayed;
    logic [31:0]        pot_integrated;
    logic               fire_comb;
    logic [31:0]        pot_next_comb;

    always_comb begin
        last_time = mem_dout_a[DATA_WIDTH-1:32];
        last_pot  = mem_dout_a[31:0];

        if (v3 && (f3 == f2)) begin
            last_time = t3;
            last_pot  = mem_din_b[31:0];
        end

        delta_t = t2 - last_time;
        decay   = delta_t >> DECAY_SHIFT;

        if (last_pot > decay)
            pot_decayed = last_pot - decay;
        else
            pot_decayed = 0;

        pot_integrated = pot_decayed + WEIGHT;

        if (pot_integrated >= nas_pkg::thresholds[f2]) begin
            fire_comb     = 1'b1;
            pot_next_comb = 32'd0;
        end else begin
            fire_comb     = 1'b0;
            pot_next_comb = pot_integrated;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            calc_pot_result <= 0;
            calc_fire       <= 0;
        end else if (v2) begin
            calc_pot_result <= pot_next_comb;
            calc_fire       <= fire_comb;
        end
    end

    assign mem_we_b  = v3;
    assign mem_din_b = {t3, calc_pot_result};

    memory #(
        .AWIDTH   (ADDR_WIDTH),
        .DWIDTH   (DATA_WIDTH),
        .RAM_TYPE ("block")
    ) ctx_mem (
        .clk      (clk),
        .mem_ena  (v1),
        .wea      (1'b0),
        .addra    (f1[ADDR_WIDTH-1:0]),
        .dina     ('0),
        .douta    (mem_dout_a),
        .mem_enb  (v3),
        .web      (1'b1),
        .addrb    (f3[ADDR_WIDTH-1:0]),
        .dinb     (mem_din_b),
        .doutb    ()
    );

    // ----------------------------------------------------------------------
    // Last Time Tracking per Window
    // ----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            prev_idx_time        <= '0;
            current_window_last_ts <= '0;
            event_seen_in_window <= 1'b0;
            last_time_out        <= '0;
            idx_time_out         <= '0;
        end else begin

            if (out_valid) begin
                current_window_last_ts <= out_t;
                event_seen_in_window   <= 1'b1;
            end

            if (idx_time_in != prev_idx_time) begin
                idx_time_out <= idx_time_in; 
                
                if (event_seen_in_window) begin
                    last_time_out <= current_window_last_ts;
                end else begin
                    last_time_out <= '0; 
                end

                prev_idx_time        <= idx_time_in;
                event_seen_in_window <= 1'b0;
                current_window_last_ts <= '0;
            end
        end
    end

endmodule