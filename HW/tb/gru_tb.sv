`timescale 1ns / 1ps

import nas_pkg::*;

module gru_ut;

    parameter MAX_X_COORD = 120;
    parameter MAX_Y_COORD = 100;
    parameter OUTPUT_PATH = "/home/pwz/Repo/SW/GRU.txt";
    parameter NS_PER_CLK = 5; // 250MHz is 4 clk every ns
    parameter TIME_WINDOW = 1000000; // We test only single time window

    logic is_valid;

    logic                      out_valid;
    logic [PRECISION_GEN-1 :0] out_conf;
    logic [PRECISION_GEN-1 :0] out_cls [CLS_NUM-1:0];
    logic [PRECISION_CONV4-1 :0] features_to_head   [OUTPUT_DIM_4-1 : 0] = {136, 136, 136, 136, 136, 136, 136, 136, 136,
                                                                            136, 136, 136, 136, 136, 136, 136, 136, 136,
                                                                            136, 136, 136, 136, 136, 136, 136, 136, 136,
                                                                            136, 136, 136, 136, 136, 136, 136, 136, 136,
                                                                            136, 136, 136, 136, 136, 136, 136, 136, 136,
                                                                            136, 136, 136, 136, 136, 136, 136, 136, 136,
                                                                            136, 136, 136, 136, 136, 136, 136, 136, 136,
                                                                            136, 136, 136, 136, 136, 136, 136, 136, 136};
    logic [PRECISION_CONV4-1 :0] features_2   [OUTPUT_DIM_4-1 : 0] = {136,136,136,136,136,136,136,136,136,137,136,136,
                                                                      136,137,136,136,136,136,136,136,136,136,136,136,
                                                                      145,136,136,136,141,136,137,136,136,136,136,143,
                                                                      136,136,136,142,136,138,136,136,136,136,136,136,
                                                                      136,136,136,136,136,136,136,136,136,136,136,136,
                                                                      136,136,136,136,136,136,136,136,136,136,136,136};
    logic clk;
    logic rst;

    // Input and output files handler, scheduler.
    int            cnt = 0;
    int            file;
    int            file_out;
    string         line;
    int            current_time_ns = 0;
    string         t_string;
    string         f_string;

    initial begin
        file_out = $fopen(OUTPUT_PATH, "w");
        while(1) begin
            if (cnt<10) begin
                rst <= 1'b1;
                cnt = cnt + 1;
            end
            else begin
                rst <= 1'b0;
            end
            #1 clk <= 1'b0;
            #1 clk <= 1'b1;
        end

    end

    always @(posedge clk) begin
        if (!rst) begin
            
            // Caluclate simulation time
            current_time_ns = current_time_ns + NS_PER_CLK;
            
            // Put values on input whenever the timestamp is smaller than simultation time
            if (1000 == current_time_ns) begin
                is_valid <= 1;
            end
            else begin
                is_valid <= 0;
                if (6000 == current_time_ns) begin
                    is_valid <= 1;
                    features_to_head <= features_2;
                end
            end

            // Write outputs to file
            if (out_valid) begin
                for (int i = 0; i < nas_pkg::CLS_NUM-1; i=i+1) begin
                    $fwrite(file_out, "%0d, ", out_cls[i]);
                end
                $fdisplay(file_out, "| %0d", out_conf);
            end

            // Finish simulation after 50.1 ms
            if (current_time_ns > 100000000) begin
                $fclose(file_out);
                $finish;
            end
        end
    end

    gru_head uut (
        .clk         ( clk              ),
        .reset       ( rst              ),
        .in_valid    ( is_valid         ),
        .in_features ( features_to_head ),
        .out_conf    ( out_conf         ),
        .out_cls     ( out_cls          ),
        .out_valid   ( out_valid        )
     );

endmodule