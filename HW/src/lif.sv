`timescale 1ns / 1ps
import nas_pkg::*;

<<<<<<< HEAD
<<<<<<< HEAD
=======
import nas_pkg::*; 

>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
module lif #(
    parameter int T_WIDTH     = 32,
    parameter int F_WIDTH     = 7,
    parameter int NUM_CHANNEL = 128,
    parameter int WEIGHT      = 32,
    parameter int DECAY_SHIFT = 8
)(
<<<<<<< HEAD
<<<<<<< HEAD
    input  logic                clk,
    input  logic                rst,
    
    input  logic                in_req,
    input  logic [T_WIDTH-1:0]  in_t,
    input  logic [F_WIDTH-1:0]  in_f,
    
    output logic                out_valid,
    output logic [T_WIDTH-1:0]  out_t,
    output logic [F_WIDTH-1:0]  out_f
);

    localparam int DATA_WIDTH = T_WIDTH + 32;
    localparam int ADDR_WIDTH = $clog2(NUM_CHANNEL);

    logic v1, v2, v3;
    logic [T_WIDTH-1:0] t1, t2, t3;
    logic [F_WIDTH-1:0] f1, f2, f3;

    logic [DATA_WIDTH-1:0] mem_dout_a;
    logic [DATA_WIDTH-1:0] mem_din_b;
    logic mem_we_b;

    logic [31:0] calc_pot_result;
    logic        calc_fire;

    always_ff @(posedge clk) begin
        if (rst) begin
            v1 <= 0; v2 <= 0; v3 <= 0;
            t1 <= '0; t2 <= '0; t3 <= '0;
            f1 <= '0; f2 <= '0; f3 <= '0;
            out_valid <= 0;
        end else begin
            v1 <= in_req;
            t1 <= in_t;
            f1 <= in_f;

            v2 <= v1;
            t2 <= t1;
            f2 <= f1;

            v3 <= v2;
            t3 <= t2;
            f3 <= f2;
            
            out_valid <= v3 && calc_fire;
            out_t     <= t3;
            out_f     <= f3;
        end
    end

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

<<<<<<< HEAD

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
=======
    input  logic                 clk,
    input  logic                 rst,
=======
    input  logic                clk,
    input  logic                rst,
>>>>>>> 7831012 (HW: modify KWS architecture for testing)

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

<<<<<<< HEAD
endmodule
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
=======
endmodule//h
>>>>>>> 7831012 (HW: modify KWS architecture for testing)
=======
endmodule
>>>>>>> 5062840 (HW: updated lif)
