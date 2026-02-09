`timescale 1ns / 1ps

import nas_pkg::*;

module handshake #(
    parameter int PRECISION_IN               = nas_pkg::PRECISION_CONV1,
    parameter int PRECISION_OUT              = nas_pkg::PRECISION_CONV1,
    parameter int INPUT_DIM                  = 72,
    parameter int OUTPUT_DIM                 = 72
)(
    input  logic clk,
    input  logic reset,
    output logic is_ready,
    input  logic is_valid,
    output logic out_valid,
    input  logic get_next
);

    logic get_next_reg;
    logic has_event = 0;

    always @(posedge clk) begin
        if (reset) begin
            is_ready <= 1'b1;
        end
        else begin
            if (is_valid && is_ready) begin
                is_ready <= '0;
            end
            if (get_next_reg) begin
                is_ready <= '1;
            end
        end
    end

    delay_module #(
        .N        ( 1  ),
        .DELAY    ( 5  )
    ) delay_enb (
        .clk   ( clk          ),
        .idata ( get_next     ),
        .odata ( get_next_reg )
    );

    assign out_valid = is_valid && is_ready;

endmodule