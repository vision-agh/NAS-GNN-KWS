`timescale 1ns / 1ps

//  Based on Language Templates - URAM/BRAM Memory
//  Xilinx UltraRAM True Dual Port Mode.

module dual_port_memory_weights #(
    parameter AWIDTH   = 16,     // Address Width
    parameter DWIDTH   = 72,     // Data Width
    parameter STEP     = 32,
    parameter RAM_TYPE = "ultra", // Memory type ("ultra" or "block"
    parameter string INIT_PATH = "/home/power-station/Repo/Event2Graph/mem/tiny_conv2_param.mem"
) ( 
    input                     clk,

    input                     en, // Memory Enable
    input [AWIDTH-1:0]        addr,   // Address Input
    output logic [DWIDTH-1:0] dout1,   // Data Output
    output logic [DWIDTH-1:0] dout2    // Data Output
);
    (* ram_style = RAM_TYPE *) logic [DWIDTH-1:0] mem[(1<<AWIDTH)-1:0]; // Memory Declaration
    initial begin
        $readmemh(INIT_PATH, mem);
    end

    logic [AWIDTH-1:0] addra, addrb;
    assign addra = addr;
    assign addrb = addr+STEP;

    // RAM : Read has one latency, Write has one latency as well.
    always @ (posedge clk) begin
        if (en) begin
            dout1 <= mem[addra];
            dout2 <= mem[addrb];
        end     
    end

endmodule
