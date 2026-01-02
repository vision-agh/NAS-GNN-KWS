`timescale 1ns / 1ps

import nas_pkg::*;

module edges_gen #(
    parameter int AWIDTH      = $clog2(NUM_CHANNEL), 
    parameter int DWIDTH      = T_WIDTH + 1,          // t + valid
    parameter int FIFO_WIDTH  = T_WIDTH + F_WIDTH + 1 // t + f + valid
)(
    input logic clk,
    input logic reset,
    input event_type                          in_event,

    output event_type                         out_event,
    output edge_type  [MAX_EDGES-1:0]         out_edges
);
    
    initial begin
        out_event <= '{default:0};
        out_edges <= '{default:0};
    end

    logic [$clog2(F_RADIUS):0] counter, counter_reg;
    event_type in_event_reg; // fifo output

    localparam IDLE = 2'd0;
    localparam GGEN = 2'd1;
    logic state = IDLE;

    // Memory interface signals
    logic [AWIDTH-1:0] addra, addrb;
    logic [DWIDTH-1:0] dinb, douta, doutb;
    logic ena, wea, web, enb;

    // Context memory instantiation
    memory #(
        .AWIDTH   ( AWIDTH  ),
        .DWIDTH   ( DWIDTH  ),
        .RAM_TYPE ( "block" )
    ) gen_memory (
        .clk      ( clk   ),
        .mem_ena  ( ena   ),    // READ only on PORTA
        .wea      ( wea   ),
        .addra    ( addra ),
        .dina     ( '0    ),
        .dinb     ( dinb  ),
        .douta    ( douta ),
        .mem_enb  ( enb   ),    // Write on last 
        .web      ( web   ),
        .addrb    ( addrb ),
        .doutb    ( doutb )
    );
    logic condition_a, condition_b, condition_a_reg, condition_b_reg;
    edge_type [MAX_EDGES-1:0] edges_reg;

    assign ena  = (counter <= F_RADIUS && condition_a && state==GGEN) ? 1'b1 : 1'b0;
    assign enb  = (counter <= F_RADIUS && condition_b && state==GGEN) ? 1'b1 : 1'b0;
    assign wea  = 0;
    assign dinb[DWIDTH-1 : 1] = in_event_reg.t;
    assign dinb[0] = 1'b1;
    assign web  = (counter == F_RADIUS) && state==GGEN;

    assign addra = in_event.f + counter*SKIP_STEP;
    assign addrb = in_event.f - (F_RADIUS*SKIP_STEP) + (counter*SKIP_STEP);

    assign condition_a = (addra >= 0) && (addra < NUM_CHANNEL);
    assign condition_b = (addrb >= 0) && (addrb < NUM_CHANNEL);

    logic [26-1 : 0] t_temp;
    logic start;
    logic [18-1 : 0] f_temp;
    logic [$clog2(MAX_EDGES)-1 : 0] num_edges;

    // Counter and edge processing
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            start <= '0;
            out_event.valid <= '0;
            counter <= F_RADIUS;
        end else begin
            if (counter < F_RADIUS && state==GGEN) begin
                counter <= counter + 1;
            end
            if (in_event.valid) begin
                counter <= '0;
                state <= GGEN;
                in_event_reg <= in_event;
            end
            if (counter_reg == F_RADIUS && counter == F_RADIUS && state == GGEN) begin
                state <= IDLE;
                start <= '1;
            end
            if (state == IDLE) begin
                if (start == 1) begin
                    out_edges <= edges_reg;
                    out_event <= in_event_reg;
                    start <= '0;
                end
                else begin
                    out_event.valid <= '0;
                end
            end
            counter_reg <= counter;
            condition_a_reg <= condition_a;
            condition_b_reg <= condition_b;

            // Port A
            edges_reg[counter_reg].dt            <= in_event_reg.t - douta[DWIDTH-1:1];
            edges_reg[counter_reg].is_connected  <= douta[0] && condition_a_reg && (T_RADIUS_LOW <= (in_event_reg.t - douta[DWIDTH-1:1]))
                                                                                && (T_RADIUS_HIGH >= (in_event_reg.t - douta[DWIDTH-1:1]));

            // Port B (ON counter F_RADIUS we do write on B)
            if (counter_reg != F_RADIUS) begin
                edges_reg[F_RADIUS+1+counter_reg].dt            <= in_event_reg.t - doutb[DWIDTH-1:1];
                edges_reg[F_RADIUS+1+counter_reg].is_connected  <= doutb[0] && condition_b_reg && (T_RADIUS_LOW <= (in_event_reg.t - doutb[DWIDTH-1:1]))
                                                                                               && (T_RADIUS_HIGH >= (in_event_reg.t - doutb[DWIDTH-1:1]));
            end
        end
    end

    // synthesis translate_off
    always @(posedge clk) begin
        if (state != IDLE && in_event.valid) begin
            $display("DECREASE THE FIFO THROUGHPUT");
            $stop;
        end
    end
    // synthesis translate_on

endmodule
