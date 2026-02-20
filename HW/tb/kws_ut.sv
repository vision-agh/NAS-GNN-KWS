`timescale 1ps / 1ps

import nas_pkg::*;

module kws_ut;

    parameter INPUT_PATH = "C:/Users/wikto/Downloads/input_events.txt";
    parameter OUTPUT_PATH = "C:/Users/wikto/NAS-GNN-KWS_OPT/SW/CONV2.txt";
    parameter TIME_WINDOW = 10000; // We test only single time window

    logic [T_WIDTH-1:0] t;
    logic [F_WIDTH:0]   f;
    logic               p;
    logic is_valid;
    logic [15:0]        idx_time = 0;
    logic [31:0]        last_time = 0;

    event_type                   event_test;
    edge_type [MAX_EDGES-1:0]    edges_test;
    logic [PRECISION_GEN-1:0]    features_test [OUTPUT_DIM_1-1 : 0];

    logic [PRECISION_GEN-1:0] t_feature;
    logic [PRECISION_GEN-1:0] f_feature;
    logic [PRECISION_GEN-1:0] p_feature;
    logic [T_WIDTH-1:0] t_feature_reg;
    logic [F_WIDTH-1:0] f_feature_reg;
    logic               p_feature_reg;
    logic [PRECISION_GEN-1 :0] out_conf_r;
    logic [(PRECISION_GEN*CLS_NUM)-1 :0] out_cls_r;
    logic out_valid_r;
    logic clock_200;
    logic clock_48;
    logic rst;

    // Queues with values from file
	logic [T_WIDTH : 0]  f_coords [$];
	logic [F_WIDTH : 0]  t_coords [$];
    logic                p_coords [$];
    logic [31:0]         last_times [$];

	logic [T_WIDTH : 0]  f_fifo [$];
	logic [F_WIDTH : 0]  t_fifo [$];
    logic                p_fifo [$];

    // Input and output files handler, scheduler.
    int            cnt = 0;
    int            file;
    int            file_out;
    string         line;
    int            current_time = 0;
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
            if (cnt<100) begin
                rst <= 1'b1;
                cnt = cnt + 1;
            end
            else begin
                rst <= 1'b0;
            end
            #2500 clock_200 <= 1'b0;
            #2500 clock_200 <= 1'b1;
        end
    end

    initial begin
        while(1) begin
            #10417 clock_48 <= 1'b0;
            #10417 clock_48 <= 1'b1;
        end
    end

    logic is_ready;
    logic get_next = 1;
    int iter = 1;
    logic [31:0] last_t = 0;
    int cnt_48 = 0;
    
    
    always @(posedge clock_48) begin
        if (!rst) begin
            cnt_48 <= cnt_48+1;
            if (cnt_48 == 47) begin
                current_time = current_time + 1;
                cnt_48 <= '0;
            end
        end
    end

    always @(posedge clock_48) begin
        if (!rst) begin
            is_valid <= 0;
            // Put values on input whenever the timestamp is smaller than simultation time
            if (t_feature_reg <= current_time) begin
                is_valid <= 1;
                f[F_WIDTH] <= p_feature_reg;
                f[F_WIDTH-1:0] <= f_feature_reg;
                t <= t_feature_reg;
                t_feature_reg <= t_coords.pop_front();
                f_feature_reg <= f_coords.pop_front();
                p_feature_reg <= p_coords.pop_front();
            end
            if (current_time >= iter*TIME_WINDOW) begin
                idx_time <= idx_time+1;
                iter <= iter+1;           
            end

 
            // Write outputs to file
            if (event_test.valid) begin
                for (int i = 0; i < nas_pkg::OUTPUT_DIM_1-1; i=i+1) begin
                    $fwrite(file_out, "%0d, ", features_test[i]);
                end
                $fdisplay(file_out, "%0d", features_test[nas_pkg::OUTPUT_DIM_1-1]);
            end

            // Finish simulation after 50.1 ms
            if (current_time > 80000) begin
                $fclose(file_out);
                $finish;
            end
        end
    end

    KWS uut (
        .clock_200(clock_200),
        .clock_48(clock_48),
        .rst_ext(rst),
        .idx_time(idx_time),
        .in_t(t),
        .in_f(f),
        .in_valid(is_valid),
        .cnn_valid(out_valid_r),
        .cnn_conf(out_conf_r),
        .cnn_class(out_cls_r)
    );

endmodule