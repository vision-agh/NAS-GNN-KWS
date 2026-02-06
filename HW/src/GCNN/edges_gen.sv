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
    output edge_type  [MAX_EDGES-1:0]         out_edges,
    output logic [$clog2(MAX_EDGES) :0]       edge_cnt
);

    initial begin
        out_event <= '{default:0};
        out_edges <= '{default:0};
    end

    localparam IDLE = 2'd0;
    localparam GGEN = 2'd1;
    logic [1:0] state, state_reg = IDLE;

    // Memory interface signals
    logic [AWIDTH-1:0] addra, addrb;
    logic [DWIDTH-1:0] din, dout;
    logic en, we;

    // Helper signals
    logic condition, condition_reg;
    logic [$clog2(MAX_EDGES) : 0] ptr = 0;
    edge_type [MAX_EDGES-1:0] edges_reg;
    logic [$clog2(MAX_EDGES):0] counter, counter_reg;
    event_type in_event_reg; // fifo output

    // Context memory instantiation
    memory #(
        .AWIDTH   ( AWIDTH  ),
        .DWIDTH   ( DWIDTH  ),
        .RAM_TYPE ( "block" )
    ) gen_memory (
        .clk      ( clk   ),
        .mem_ena  ( en    ),    // READ only on PORTA
        .wea      ( '0    ),
        .addra    ( addra ),
        .dina     ( '0    ),
        .douta    ( dout  ),
        .mem_enb  ( we    ),    // Write on last 
        .web      ( we    ),
        .addrb    ( addrb ),
        .dinb     ( din   ),
        .doutb    ( )
    );

    // [Read] Logic on counter (memory_in)
    assign en  = (counter < MAX_EDGES) && condition && state==GGEN ? 1'b1 : 1'b0;
    assign addra = (counter <= F_RADIUS) ? in_event.f + counter*SKIP_STEP : in_event.f - ((counter-F_RADIUS)*SKIP_STEP);
    assign condition = (addra >= 0) && (addra < NUM_CHANNEL);

    // [Write] Logic on counter (memory_in)
    assign we  = (counter == MAX_EDGES-1) && state==GGEN;
    assign din[DWIDTH-1 : 1] = in_event_reg.t;
    assign din[0] = 1'b1;
    assign addrb = in_event_reg.f;
    logic start;

    // Counter and edge processing
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            start <= '0;
            out_event.valid <= '0;
            edge_cnt <= '0;
            counter <= F_RADIUS;
        end else begin
            if (counter < MAX_EDGES-1 && state==GGEN) begin
                counter <= counter + 1;
            end
            if (in_event.valid) begin
                counter <= '0;
                ptr <= '0;
                state <= GGEN;
                in_event_reg <= in_event;
                edge_cnt <= '0;
            end
            if (counter_reg == MAX_EDGES-1 && state_reg == GGEN) begin
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
                edges_reg <= '{default:0};
            end
            counter_reg <= counter;
            condition_reg <= condition;
            state_reg <= state;

            edges_reg[ptr].dt            <= in_event_reg.t - dout[DWIDTH-1:1];
            edges_reg[ptr].df            <= counter_reg;
            if (state_reg == GGEN && dout[0] && condition_reg && (T_RADIUS_LOW <= (in_event_reg.t - dout[DWIDTH-1:1]))
                                         && (T_RADIUS_HIGH >= (in_event_reg.t - dout[DWIDTH-1:1]))) begin
                edges_reg[ptr].is_connected <= 1'b1;
                ptr <= ptr + 1; 
                edge_cnt <= edge_cnt + 1;
            end
            else begin
                edges_reg[ptr].is_connected <= 1'b0;
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
