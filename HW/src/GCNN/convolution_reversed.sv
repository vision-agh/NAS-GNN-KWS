`timescale 1ns / 1ps

import nas_pkg::*;

module convolution_reversed #(
    parameter int PRECISION_IN               = nas_pkg::PRECISION_CONV1,
    parameter int PRECISION_OUT              = nas_pkg::PRECISION_CONV1,
    parameter int INPUT_DIM                  = 2,
    parameter int MEMORY_FACTOR              = 2,
    parameter int OUTPUT_DIM                 = 64,
    parameter int MULTIPLIER_DIFF_T          = 214742,
    parameter int ZERO_POINT_IN              = 0,
    parameter int ZERO_POINT_OUT             = 135,
    parameter int MULTIPLIER_OUT             = 58670,
    parameter int ZERO_POINT_WEIGHT          = 30075,
    parameter string INIT_PATH               = "???",
    parameter logic [PRECISION_IN-1:0] SCALE_IN [21:0] = { 32767, 29490, 26214, 22937, 19660, 16383, 13107, 9830, 6553, 3277, 0, 65534,
                                                             62257, 58981, 55704, 52427, 49150, 45874, 42597, 39320, 36044, 32767 }
)(
    input logic clk,
    input logic reset,
    input event_type                   in_event,
    output logic                       in_ready,
    input edge_type  [MAX_EDGES-1:0]   in_edges,
    input logic [PRECISION_IN-1 :0]    in_features [INPUT_DIM-1 : 0],
    input logic [$clog2(MAX_EDGES) :0] in_edge_cnt,

    output event_type                   out_event,
    output edge_type  [MAX_EDGES-1:0]   out_edges,
    output logic [PRECISION_OUT-1 :0]   out_features [OUTPUT_DIM-1 : 0],
    output logic [$clog2(MAX_EDGES) :0] out_edge_cnt
);

    typedef logic [PRECISION_IN-1 :0] features_type [INPUT_DIM-1 : 0];
    typedef logic [(PRECISION_IN*(INPUT_DIM/MEMORY_FACTOR))-1 :0] memory_type;
    localparam AWIDTH = $clog2(NUM_CHANNEL*MEMORY_FACTOR);
    localparam DWIDTH = (INPUT_DIM/MEMORY_FACTOR) * PRECISION_IN;

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
    logic [1:0] state, state_MRR, state_RM, state_mul_in = IDLE;
    logic [$clog2(MEMORY_FACTOR):0]                fraction_counter;
    logic [$clog2(F_RADIUS):0]                     iter_counter, iter_counter_MRR, iter_counter_RM, iter_counter_acc;
    logic [$clog2((OUTPUT_DIM*MEMORY_FACTOR)/2):0] outdim_counter, outdim_counter_mul_out, outdim_counter_compare, outdim_counter_acc;

    delay_module #(
        .N        ( $clog2(F_RADIUS)+1 ),
        .DELAY    ( 12                 )
    ) delay_counter (
        .clk   ( clk              ),
        .idata ( iter_counter     ),
        .odata ( iter_counter_acc )
    );

    delay_module #(
        .N        ( $clog2(OUTPUT_DIM)+1 ),
        .DELAY    ( 10                   )
    ) delay_out_counter (
        .clk   ( clk                    ),
        .idata ( outdim_counter         ),
        .odata ( outdim_counter_mul_out )
    );

    /////////////////////////////////////////////////////////////////
    //                        Handle MEMORY                        //
    /////////////////////////////////////////////////////////////////

    // Memory interface signals
    logic [AWIDTH-1:0] addra, addrb;
    logic [DWIDTH-1:0] dina, dinb, douta, doutb;
    logic ena, ena_RM, we, enb, enb_RM;

    // State machine
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            fraction_counter <= '0;
            iter_counter <= '0;
            outdim_counter <= '0;
        end else begin
            if (state == IDLE) begin
                event_reg.valid <= '0;
                in_ready <= '1;
            end
            if (in_event.valid) begin
                iter_counter <= '0;
                in_ready <= '0;
                outdim_counter <= '0;
                fraction_counter <= '0;
                state <= CONV;
                event_reg <= in_event;
                event_reg.valid <= '0;
                edges_reg <= in_edges;
                features_reg <= in_features;
                edge_cnt_reg <= in_edge_cnt;
                num_iter <= ((in_edge_cnt+1) % 2) ? ((in_edge_cnt+2) / 2)-1 : ((in_edge_cnt+1) / 2)-1;
            end
            if (state == CONV) begin
                fraction_counter <= fraction_counter+1;
                if (fraction_counter == MEMORY_FACTOR-1) begin
                    fraction_counter <= '0;
                    outdim_counter <= outdim_counter + 1;
                    if (outdim_counter == (((OUTPUT_DIM*MEMORY_FACTOR)/2)-1)) begin
                        if (iter_counter < num_iter) begin
                            iter_counter <= iter_counter + 1;
                            outdim_counter <= '0;
                        end
                        else begin
                            state <= SAVE;
                        end
                    end
                end
            end
            if (state == SAVE) begin
                state <= IDLE;
                event_reg.valid <= 1;
            end
            state_MRR <= state;
            state_RM <= state_MRR;
            state_mul_in <= state_RM;
            
            iter_counter_MRR <= iter_counter;
            iter_counter_RM <= iter_counter_MRR;
            ena_RM <= ena;
            enb_RM <= enb;
            
            outdim_counter_compare <= outdim_counter_mul_out;
            outdim_counter_acc <= outdim_counter_compare;
        end
    end

    logic [$clog2(MAX_EDGES) :0] idx_a, idx_a_RM;
    logic [$clog2(MAX_EDGES) :0] idx_b, idx_b_RM;

    assign idx_a = iter_counter_MRR != 0 ? ((iter_counter_MRR*2)-1) : 0;
    assign idx_b = iter_counter_MRR*2;

    // Context memory
    assign ena  = we || ((state_MRR == CONV) && iter_counter_MRR != 0 && edges_reg[idx_a].is_connected);
    assign enb  = we || ((state_MRR == CONV) && edges_reg[idx_b].is_connected);
    assign dina = memory_type'(features_reg[35:0]);
    assign dinb = memory_type'(features_reg[71:36]);
    assign we  = state_MRR == SAVE;

    assign addra = (edges_reg[idx_a].df <= F_RADIUS) ? event_reg.f + edges_reg[idx_a].df*SKIP_STEP :
                                                                     event_reg.f - ((edges_reg[idx_a].df-F_RADIUS)*SKIP_STEP);
    assign addrb = (state_MRR == SAVE) ? event_reg.f+INPUT_DIM : 
                   ((edges_reg[idx_b].df <= F_RADIUS) ? event_reg.f + edges_reg[idx_b].df*SKIP_STEP :
                                                        event_reg.f - ((edges_reg[idx_b].df-F_RADIUS)*SKIP_STEP));

    always @(posedge clk) begin
        idx_a_RM <= idx_a;
        idx_b_RM <= idx_b;
    end

    memory #(
        .AWIDTH   ( AWIDTH  ),
        .DWIDTH   ( DWIDTH  ),
        .RAM_TYPE ( "block" )
    ) gen_memory (
        .clk      ( clk                                ),
        .mem_ena  ( ena                                ),
        .wea      ( we                                 ),
        .addra    ( addra+(INPUT_DIM*fraction_counter) ),
        .dina     ( dina                               ),
        .dinb     ( dinb                               ),
        .douta    ( douta                              ),
        .mem_enb  ( enb                                ),
        .web      ( we                                 ),
        .addrb    ( addrb+(INPUT_DIM*fraction_counter) ),
        .doutb    ( doutb                              )
    );



    // synthesis translate_off
//    always @(posedge clk) begin
//        if (state != IDLE && in_event.valid) begin
//            $display("DECREASE THE FIFO THROUGHPUT");
//            $stop;
//        end
//    end
    // synthesis translate_on

endmodule