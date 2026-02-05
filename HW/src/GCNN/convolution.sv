`timescale 1ns / 1ps

import nas_pkg::*;

module convolution #(
    parameter int PRECISION_IN               = nas_pkg::PRECISION_CONV1,
    parameter int PRECISION_OUT              = nas_pkg::PRECISION_CONV1,
    parameter int INPUT_DIM                  = 2,
    parameter int OUTPUT_DIM                 = 64,
    parameter int MULTIPLIER_DIFF_T          = 214742, //good
    parameter int ZERO_POINT_IN              = 0,  //good
    parameter int ZERO_POINT_OUT             = 36533, //good
    parameter int MULTIPLIER_OUT             = 58670, //good
    parameter int ZERO_POINT_WEIGHT          = 30075,
    parameter string INIT_PATH               = "???",
    parameter logic [PRECISION_IN-1:0] SCALE_IN [21:0]   = { 32767, 29490, 26214, 22937, 19660, 16383, 13107, 9830, 6553, 3277, 0, 65534,
                                                             62257, 58981, 55704, 52427, 49150, 45874, 42597, 39320, 36044, 32767 }
)(
    input logic clk,
    input logic reset,
    input event_type                        in_event,
    input edge_type  [MAX_EDGES-1:0]        in_edges,
    input logic [PRECISION_IN-1 :0]         in_features [INPUT_DIM-1 : 0],
    input logic      [$clog2(MAX_EDGES) :0] in_edge_cnt,

    output event_type                        out_event,
    output edge_type  [MAX_EDGES-1:0]        out_edges,
    output logic [PRECISION_OUT-1 :0]        out_features [OUTPUT_DIM-1 : 0],
    output logic      [$clog2(MAX_EDGES) :0] out_edge_cnt
);

    typedef logic [PRECISION_IN-1 :0] features_type [INPUT_DIM-1 : 0];
    typedef logic [(PRECISION_IN*INPUT_DIM)-1 :0] memory_type;
    localparam AWIDTH = $clog2(NUM_CHANNEL);
    localparam DWIDTH = INPUT_DIM * PRECISION_IN;

    // Process:
    // cnt - save internal state
    // MRR - MemoryReadRequest
    // RM - ReadMemory


    // Internal state - ready on RM
    event_type                        event_reg;
    edge_type  [MAX_EDGES-1:0]        edges_reg;
    logic      [$clog2(MAX_EDGES) :0] edge_cnt_reg;
    logic [$clog2(MAX_EDGES/2) :0]    num_iter;
    features_type                     features_reg;

    // STATE MACHINE:
    // IDLE - wait
    // CONV - convolution
    // SAVE - sending data and saving features
    localparam IDLE = 2'd0;
    localparam CONV = 2'd1;
    localparam SAVE = 2'd2;
    logic [1:0] state, state_MRR = IDLE;
    logic [$clog2(F_RADIUS):0]     iter_counter, iter_counter_MRR;
    logic [$clog2(OUTPUT_DIM/2):0] outdim_counter;

    // Memory interface signals
    logic [AWIDTH-1:0] addra, addrb;
    logic [DWIDTH-1:0] dinb, douta, doutb;
    logic ena, web, enb;

    // State machine
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            iter_counter <= '0;
            outdim_counter <= '0;
        end else begin
            if (in_event.valid) begin
                iter_counter <= '0;
                outdim_counter <= '0;
                state <= CONV;
                event_reg <= in_event;
                edges_reg <= in_edges;
                features_reg <= in_features;
                edge_cnt_reg <= in_edge_cnt;
                num_iter <= ((in_edge_cnt+1) % 2) ? ((in_edge_cnt+2) / 2)-1 : ((in_edge_cnt+1) / 2)-1;
            end
            if (state == CONV) begin
                outdim_counter <= outdim_counter + 1;
                if (outdim_counter == ((OUTPUT_DIM/2)-1)) begin
                    if (iter_counter < num_iter) begin
                        iter_counter <= iter_counter + 1;
                        outdim_counter <= '0;
                    end
                    else begin
                        state <= SAVE;
                    end
                end
            end
            if (state == SAVE) begin
                state <= IDLE;
            end
            state_MRR <= state;
            iter_counter_MRR <= iter_counter;
        end
    end

    logic [$clog2(MAX_EDGES) :0] idx_a;
    logic [$clog2(MAX_EDGES) :0] idx_b;

    assign idx_a = iter_counter_MRR != 0 ? ((iter_counter_MRR*2)-1) : 0;
    assign idx_b = iter_counter_MRR*2;

    // Context memory
    assign ena  = (state_MRR == CONV) && iter_counter_MRR != 0 && edges_reg[idx_a].is_connected;
    assign enb  = web || ((state_MRR == CONV) && edges_reg[idx_b].is_connected);
    assign dinb = memory_type'(features_reg);
    assign web  = state_MRR == SAVE;

    assign addra = (edges_reg[idx_a].df <= F_RADIUS) ? event_reg.f + edges_reg[idx_a].df*SKIP_STEP :
                                                                     event_reg.f - ((edges_reg[idx_a].df-F_RADIUS)*SKIP_STEP);
    assign addrb = (state_MRR == SAVE) ? event_reg.f : 
                   ((edges_reg[idx_b].df <= F_RADIUS) ? event_reg.f + edges_reg[idx_b].df*SKIP_STEP :
                                                                      event_reg.f - ((edges_reg[idx_b].df-F_RADIUS)*SKIP_STEP));

    memory #(
        .AWIDTH   ( AWIDTH  ),
        .DWIDTH   ( DWIDTH  ),
        .RAM_TYPE ( "block" )
    ) gen_memory (
        .clk      ( clk   ),
        .mem_ena  ( ena   ),    // READ only on PORTA
        .wea      ( '0    ),
        .addra    ( addra ),
        .dina     ( '0    ),
        .dinb     ( dinb  ),
        .douta    ( douta ),
        .mem_enb  ( enb   ),    // Write on last 
        .web      ( web   ),
        .addrb    ( addrb ),
        .doutb    ( doutb )
    );


    // synthesis translate_off
    always @(posedge clk) begin
        if (state != IDLE && in_event.valid) begin
            $display("DECREASE THE FIFO THROUGHPUT");
            $stop;
        end
    end
    // synthesis translate_on

endmodule

