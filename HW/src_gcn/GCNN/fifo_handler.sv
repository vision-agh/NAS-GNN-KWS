`timescale 1ns / 1ps

import nas_pkg::*;


module fifo_handler #(
    parameter THROUGHTPUT = 400
)(
    input  logic                              clk,
    input  logic                              reset,
    input  logic signed     [T_WIDTH-1:0]     t,
    input  logic signed     [F_WIDTH-1:0]     f,
    input  logic                              is_valid,
    // input  logic                              is_last,
    output event_type                         out_event

);
    localparam FIFO_WIDTH = T_WIDTH + F_WIDTH + 1;

    logic wen, fifo_read, empty, full, fifo_read_reg;
    logic [$clog2(THROUGHTPUT) : 0] counter;
    logic  [FIFO_WIDTH-1:0] din, dout;

    // assign din = {t, f, is_last};
    assign din = {t, f};
    assign wen = !full && is_valid;

    fifo_generator_0 fifo_0 (
        .clk      ( clk        ),
        .wr_en    ( wen       ),
        .din      ( din       ),
        .full     ( full      ),
        .rd_en    ( fifo_read ),
        .dout     ( dout      ),
        .empty    ( empty     )
    );
    
        //vck190
//    fifo_generator_0_0 fifo_0 (
//        .wr_clk   ( clk       ),
//        .wr_en    ( wen       ),
//        .din      ( din       ),
//        .full     ( full      ),
//        .rd_en    ( fifo_read ),
//        .dout     ( dout      ),
//        .empty    ( empty     )
//    );

    always @(posedge clk) begin
        if (reset) begin
            counter <= '0;
            out_event.valid <= '0;
        end else begin
            out_event.valid <= fifo_read;
            if (counter == THROUGHTPUT) begin
                if (!empty) begin
                    counter <= 0;
                end                
            end
            else begin
                counter <= counter + 1;
            end
        end
    end

    assign fifo_read = (counter == THROUGHTPUT) && !empty;
    assign out_event.t = dout[(T_WIDTH+F_WIDTH):F_WIDTH+1];
    assign out_event.f = dout[F_WIDTH:1];
    // assign out_event.is_last = dout[0];

endmodule
