`timescale 1ns / 1ps

module lif #(
    parameter int T_WIDTH      = 32,
    parameter int F_WIDTH      = 7,
    parameter int NUM_CHANNEL  = 128,
    parameter int WEIGHT       = 50,
    parameter int DECAY_SHIFT  = 4
)(
    input  logic                clk,
    input  logic                rst,

    // Input Stream
    input  logic                in_req,
    input  logic [T_WIDTH-1:0]  in_t,
    input  logic [F_WIDTH-1:0]  in_f,

    // Output Stream
    output logic                out_valid,
    output logic [T_WIDTH-1:0]  out_t,
    output logic [F_WIDTH-1:0]  out_f
);


    localparam int MEM_DWIDTH = T_WIDTH + T_WIDTH; 
    localparam int MEM_AWIDTH = F_WIDTH;

    logic                  mem_en_a, mem_en_b;
    logic                  we_b;
    logic [MEM_AWIDTH-1:0] addr_a, addr_b;
    logic [MEM_DWIDTH-1:0] dout_a;
    logic [MEM_DWIDTH-1:0] din_b;


    typedef struct packed {
        logic                 valid;
        logic [T_WIDTH-1:0]   t;
        logic [F_WIDTH-1:0]   f;
    } pipe_reg_t;

    pipe_reg_t s1_reg;

    assign addr_a   = in_f;
    assign mem_en_a = 1'b1; 

    always_ff @(posedge clk) begin
        if (rst) begin
            s1_reg.valid <= 1'b0;
            s1_reg.t     <= '0;
            s1_reg.f     <= '0;
        end else begin
            s1_reg.valid <= in_req;
            s1_reg.t     <= in_t;
            s1_reg.f     <= in_f;
        end
    end


    memory #(
        .AWIDTH   (MEM_AWIDTH),
        .DWIDTH   (MEM_DWIDTH), 
        .RAM_TYPE ("block")
    ) ctx_mem (
        .clk      (clk),
        
        // Port A: Read Old State
        .mem_ena  (mem_en_a),
        .wea      (1'b0),
        .addra    (addr_a),
        .dina     ('0),
        .douta    (dout_a), 
        
        // Port B: Write New State
        .mem_enb  (mem_en_b),
        .web      (we_b),
        .addrb    (addr_b),
        .dinb     (din_b),
        .doutb    ()
    );


    logic [T_WIDTH-1:0] r_last_time;
    logic [T_WIDTH-1:0] r_current_pot;
    
    assign r_last_time   = dout_a[T_WIDTH-1:0];
    assign r_current_pot = dout_a[2*T_WIDTH-1 : T_WIDTH];

    logic [T_WIDTH-1:0] delta_t;
    logic [T_WIDTH-1:0] decay;
    logic [T_WIDTH-1:0] pot_after_decay; 
    logic [T_WIDTH-1:0] pot_new;
    logic [T_WIDTH-1:0] next_pot_to_save;
    logic               fire_condition;
    logic [T_WIDTH-1:0] current_threshold;

    assign current_threshold = nas_pkg::thresholds[s1_reg.f];

    assign delta_t         = s1_reg.t - r_last_time;
    assign decay           = delta_t >> DECAY_SHIFT;
    assign pot_after_decay = (r_current_pot > decay) ? (r_current_pot - decay) : '0;
    
    assign pot_new         = pot_after_decay + WEIGHT;
    assign fire_condition  = (pot_new >= current_threshold);

    assign next_pot_to_save = fire_condition ? '0 : pot_new;

    assign addr_b   = s1_reg.f;
    assign mem_en_b = s1_reg.valid;
    assign we_b     = s1_reg.valid;      
    assign din_b    = {next_pot_to_save, s1_reg.t};

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            out_t     <= '0;
            out_f     <= '0;
        end else begin
            out_valid <= s1_reg.valid && fire_condition;
            out_t     <= s1_reg.t;
            out_f     <= s1_reg.f;
        end
    end

endmodule//h