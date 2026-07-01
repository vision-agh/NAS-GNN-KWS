`timescale 1ns / 1ps

import nas_pkg::*;

module handle_memory #(
    parameter int FEATURE_DIM = 72,
    parameter int PRECISION = 8,
    parameter int MEMORY_FACTOR = 8,
    parameter int AWIDTH = $clog2(NUM_CHANNEL*MEMORY_FACTOR),
    parameter int DWIDTH = (FEATURE_DIM/MEMORY_FACTOR) * PRECISION
)( 
    input  logic                           clk,
    input  logic                           reset,
    input  logic                           get_feature,
    input  logic                           save_feature,
    input  logic [$clog2(NUM_CHANNEL): 0]  ref_addr,
    input  logic [PRECISION-1:0]           in_feature [FEATURE_DIM-1:0],
    output logic [PRECISION-1:0]           out_feature [FEATURE_DIM-1:0],
    output logic                           feature_done
);

    typedef logic [PRECISION-1 :0] factor_type [(FEATURE_DIM/MEMORY_FACTOR)-1 : 0];
    typedef logic [DWIDTH-1 :0] memory_type;

    logic [AWIDTH-1:0] addra, addrb;
    memory_type   dina, dinb, douta, doutb;
    factor_type douta_features;
    factor_type doutb_features;
    factor_type dina_features;
    factor_type dinb_features;

    logic en, we, write;
    logic [$clog2(MEMORY_FACTOR/2) : 0] counter, counter_reg;

    always @(posedge clk) begin
        if (reset) begin
            en <= '0;
            we <= '0;
            write <= '0;
            counter <= '0;
            counter_reg <= '0;
            feature_done <= '0;
        end
        else begin
            // ON COUNTER
            if (get_feature)  en <= 1'b1;
            if (save_feature) begin
                write <= '1;
            end

            if (en) begin
                counter <= counter +1;
                if (counter == ((MEMORY_FACTOR/2)-1)) begin
                    en <= '0;
                    counter <= '0;
                end
            end

            we <= '0;
            if (write) begin
                counter <= counter +1;
                we <= 1;
                if (counter == ((MEMORY_FACTOR/2)-1)) begin
                    write <= '0;
                    counter <= '0;
                end
            end

            counter_reg <= counter;

            if (counter_reg == ((MEMORY_FACTOR/2)-1)) begin
                feature_done <= 1'b1;
            end
            if (feature_done) begin
                feature_done <= '0;
            end
        end
    end

    genvar w;
    generate
        for (w = 0; w < (FEATURE_DIM/MEMORY_FACTOR); w++) begin : weights_assign
            always @(posedge clk) begin
                dina_features[w] <= in_feature[w+(counter*(FEATURE_DIM/MEMORY_FACTOR))];
                dinb_features[w] <= in_feature[36+w+(counter*(FEATURE_DIM/MEMORY_FACTOR))];
                out_feature[w+(counter_reg*(FEATURE_DIM/MEMORY_FACTOR))] <= douta_features[w];
                out_feature[36+w+(counter_reg*(FEATURE_DIM/MEMORY_FACTOR))] <= doutb_features[w];
            end
        end
    endgenerate

    //  1  2  3  4  5  6  7  8
    // 37 38 39 40 41 42 43 44
    
    //  9 10 11 12 13 14 15 16
    // 45 46 47 48 49 50 51 52

    assign addra = we ? (ref_addr + (counter_reg*NUM_CHANNEL)) : (ref_addr + (counter*NUM_CHANNEL));
    assign addrb = we ? (ref_addr + ((counter_reg+(MEMORY_FACTOR/2))*NUM_CHANNEL)) : 
                        (ref_addr + ((counter+(MEMORY_FACTOR/2))*NUM_CHANNEL));

    assign douta_features = factor_type'(douta);
    assign doutb_features = factor_type'(doutb);
    assign dina = memory_type'(dina_features);
    assign dinb = memory_type'(dinb_features);

    memory #(
        .AWIDTH   ( AWIDTH  ),
        .DWIDTH   ( DWIDTH  ),
        .RAM_TYPE ( "block" )
    ) gen_memory (
        .clk      ( clk      ),
        .mem_ena  ( en || we ),
        .wea      ( we       ),
        .addra    ( addra    ),
        .dina     ( dina     ),
        .dinb     ( dinb     ),
        .douta    ( douta    ),
        .mem_enb  ( en || we ),
        .web      ( we       ),
        .addrb    ( addrb    ),
        .doutb    ( doutb    )
    );

endmodule