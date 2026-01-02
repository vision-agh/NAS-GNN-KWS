`timescale 1ns / 1ps

import nas_pkg::*;

module gcnn_ut;

    parameter MAX_X_COORD = 120;
    parameter MAX_Y_COORD = 100;
    parameter INPUT_PATH = "/home/pwz/Repo/SW/NAS-GNN-KWS/SW/example_result/kws/20251223_113159/debug_outputs/filtered_events.txt";
    parameter OUTPUT_PATH = "/home/pwz/Repo/SW/CONV4.txt";
    parameter NS_PER_CLK = 5; // 250MHz is 4 clk every ns
    parameter TIME_WINDOW = 1000000; // We test only single time window

    logic [T_WIDTH-1:0] t;
    logic [F_WIDTH-1:0] f;
    logic is_valid;

    event_type                   event_test;
    edge_type [MAX_EDGES-1:0]    edges_test;
    logic [PRECISION_GEN-1:0]    features_test [OUTPUT_DIM_1-1 : 0];

    logic [PRECISION_GEN-1:0] t_feature;
    logic [PRECISION_GEN-1:0] f_feature;
    logic [T_WIDTH-1:0] t_feature_reg;
    logic [F_WIDTH-1:0] f_feature_reg;

    logic clk;
    logic rst;

    // Queues with values from file
	logic [T_WIDTH : 0]  f_coords [$];
	logic [F_WIDTH : 0]  t_coords [$];

    // Input and output files handler, scheduler.
    int            cnt = 0;
    int            file;
    int            file_out;
    string         line;
    int            current_time_ns = 49000;
    string         t_string;
    string         f_string;

    initial begin
        file = $fopen(INPUT_PATH, "r");
        file_out = $fopen(OUTPUT_PATH, "w");

        while(!$feof(file)) begin
            $fgets(line, file);
            $sscanf (line, "%s %s %s %s", t_string, f_string);
            
            // Save coordinates
            t_coords.push_back(t_string.atoi());
            f_coords.push_back(f_string.atoi());

        end
        $fclose(file);

        // Get first values from queue
        t_feature_reg   = t_coords.pop_front();
        f_feature_reg   = f_coords.pop_front();

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
            if (t_feature_reg * 1000 < current_time_ns && t_feature_reg <= TIME_WINDOW) begin
                is_valid <= 1;
                t_feature_reg   <= t_coords.pop_front();
                f_feature_reg   <= f_coords.pop_front();
            end
            else begin
                 is_valid <= 0;
            end

            t <= t_feature_reg;
            f <= f_feature_reg;

            // Write outputs to file
            if (event_test.valid) begin
                for (int i = 0; i < nas_pkg::OUTPUT_DIM_1-1; i=i+1) begin
                    $fwrite(file_out, "%0d, ", features_test[i]);
                end
                $fdisplay(file_out, "%0d", features_test[nas_pkg::OUTPUT_DIM_1-1]);
            end

            // Finish simulation after 50.1 ms
            if (current_time_ns > 100000000) begin
                $fclose(file_out);
                $finish;
            end
        end
    end

    gcnn_top uut (
        .clk(clk),
        .reset(rst),
        .t(t),
        .f(f),
        .is_valid(is_valid),
        .event_test(event_test),
        .edges_test(edges_test),
        .features_test(features_test)
    );

endmodule