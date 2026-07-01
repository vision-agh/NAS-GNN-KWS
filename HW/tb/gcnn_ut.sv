`timescale 1ns / 1ps

import nas_pkg::*;

module gcnn_ut;

    parameter MAX_X_COORD = 120;
    parameter MAX_Y_COORD = 100;
    parameter INPUT_PATH = "/home/pwz/Downloads/20260204_231115_job12165103_task2_x1002c4s5b1n0/debug_outputs/filtered_events.txt";
    parameter OUTPUT_PATH = "/home/pwz/Repo/SW/CONV2.txt";
    parameter NS_PER_CLK = 5; // 250MHz is 4 clk every ns
    parameter TIME_WINDOW = 1000000; // We test only single time window

    logic [T_WIDTH-1:0] t;
    logic [F_WIDTH-1:0] f;
    logic               p;
    logic is_valid = 0;

    event_type                   event_test;
    edge_type [MAX_EDGES-1:0]    edges_test;
    logic [PRECISION_GEN-1:0]    features_test [OUTPUT_DIM_1-1 : 0];

    logic [PRECISION_GEN-1:0] t_feature;
    logic [PRECISION_GEN-1:0] f_feature;
    logic [PRECISION_GEN-1:0] p_feature;
    logic [T_WIDTH-1:0] t_feature_reg;
    logic [F_WIDTH-1:0] f_feature_reg;
    logic               p_feature_reg;

    logic clk;
    logic rst;

    // Queues with values from file
	logic [T_WIDTH : 0]  f_coords [$];
	logic [F_WIDTH : 0]  t_coords [$];
    logic                p_coords [$];

    // Input and output files handler, scheduler.
    int            cnt = 0;
    int            file;
    int            file_out;
    string         line;
    int            current_time_ns = 49000;
    string         t_string;
    string         f_string;
    string         p_string;

    initial begin
        file = $fopen(INPUT_PATH, "r");
        file_out = $fopen(OUTPUT_PATH, "w");

        while(!$feof(file)) begin
            $fgets(line, file);
            $sscanf (line, "%s %s %s", t_string, f_string, p_string);
            
            // Save coordinates
            t_coords.push_back(t_string.atoi());
            f_coords.push_back(f_string.atoi());
            if (p_string == "1") begin
                p_coords.push_back(1'b1);
            end
            else begin
                p_coords.push_back(1'b0);
            end
            

        end
        $fclose(file);

        // Get first values from queue
        t_feature_reg = t_coords.pop_front();
        f_feature_reg = f_coords.pop_front();
        p_feature_reg = p_coords.pop_front();
        
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

    logic is_ready;

    always @(posedge clk) begin
        if (!rst) begin
            
            // Caluclate simulation time
            current_time_ns = current_time_ns + NS_PER_CLK;
//            is_ready <= 1'b0;
//            if (current_time_ns % 2000 == 0) begin
//                is_ready <= 1'b1;
//            end
//            // Put values on input whenever the timestamp is smaller than simultation time
//            if (t_feature_reg * 1000 < current_time_ns && t_feature_reg <= TIME_WINDOW) begin
//                is_valid <= 1;
//                t_feature_reg   <= t_coords.pop_front();
//                f_feature_reg   <= f_coords.pop_front();
//            end
//            else begin
//                 is_valid <= 0;
//            end
            is_valid <= '1;
            // Put values on input whenever the timestamp is smaller than simultation time
            if (is_ready && is_valid) begin
                t_feature_reg <= t_coords.pop_front();
                f_feature_reg <= f_coords.pop_front();
                p_feature_reg <= p_coords.pop_front();
            end

            t <= t_feature_reg;
            f <= f_feature_reg;
            p <= p_feature_reg;

            // Write outputs to file
            if (event_test.valid) begin
                for (int i = 0; i < nas_pkg::OUTPUT_DIM_1-1; i=i+1) begin
                    $fwrite(file_out, "%0d, ", features_test[i]);
                end
                $fdisplay(file_out, "%0d", features_test[nas_pkg::OUTPUT_DIM_1-1]);
            end

            // Finish simulation after 50.1 ms
            if (current_time_ns > 3000000) begin
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
        .p(p),
        .is_valid(is_valid),
        .is_ready(is_ready),
        .event_test(event_test),
        .edges_test(edges_test),
        .features_test(features_test)
    );

endmodule