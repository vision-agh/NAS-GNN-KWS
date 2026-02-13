`timescale 1ns / 1ps

//  Based on Language Templates - URAM/BRAM Memory
//  Xilinx UltraRAM True Dual Port Mode.

module single_port_memory_weights #(
    parameter AWIDTH   = 16,     // Address Width
    parameter DWIDTH   = 72,     // Data Width
    parameter RAM_TYPE = "ultra", // Memory type ("ultra" or "block"
    parameter string INIT_PATH = "/home/power-station/Repo/Event2Graph/mem/tiny_conv2_param.mem"
) ( 
    input                     clk,

    input                     en, // Memory Enable
    input [AWIDTH-1:0]        addr,   // Address Input
    output logic [DWIDTH-1:0] dout   // Data Output
);
    (* ram_style = RAM_TYPE *) logic [DWIDTH-1:0] mem[(1<<AWIDTH)-1:0]; // Memory Declaration
    initial begin
        $readmemh(INIT_PATH, mem);
    end

    logic [AWIDTH-1:0] addra;
    assign addra = addr;

    // RAM : Read has one latency, Write has one latency as well.
    always @ (posedge clk) begin
        if (en) begin
            dout <= mem[addra];
        end     
    end

endmodule
