package nas_pkg;


    parameter F_RADIUS   = 5; //Search radius will be F_RADIUS*SKIPSTEPS                    
    parameter T_RADIUS_LOW   = 0;
    parameter T_RADIUS_HIGH = 5000;           
    parameter SKIP_STEP = 1;        
    parameter MAX_EDGES  = (F_RADIUS*2) + 1; //the same F neighbour possible!;         
    parameter PRECISION_GEN  = 8;                    
    parameter PRECISION_CONV1  = 8;                    
    parameter PRECISION_CONV2  = 8;                    
    parameter PRECISION_CONV3  = 8;                    
    parameter PRECISION_CONV4  = 8;                    
    parameter CLS_NUM = 11;

    parameter T_WIDTH  = 32; //Max of 1000000
    parameter T_DIFF_WIDTH  = 15; //Max of 20000
    parameter F_WIDTH  = 5; //Max of 64

    parameter NUM_CHANNEL = 32;

    parameter INPUT_PARAMETER = 2; 
    parameter INPUT_DIM_1 = 3; 
    parameter OUTPUT_DIM_1 = 72;
    parameter OUTPUT_DIM_2 = 72;
    parameter OUTPUT_DIM_3 = 72;
    parameter OUTPUT_DIM_4 = 72;

      typedef struct packed {
      logic [T_WIDTH -1: 0] t;
      logic [F_WIDTH -1: 0] f;
      logic                 p;
      logic                 valid;
    } event_type;

    typedef struct packed {
      logic [T_DIFF_WIDTH-1 : 0] dt;
      logic [4 : 0]              df;
      logic                      is_connected;
    } edge_type;

    parameter DELTA_T_WIDTH = 15; //max value of 20000
    parameter GEN_MULTIPLIER_T = 424422;
    parameter [63:0] GEN_MULTIPLIER_F = 64'd13263200211; // (add 2^32)
    parameter GEN_ZERO_POINT = 99;

    // LIF parameters
    parameter DECAY_SHIFT = 8;
    parameter WEIGHT = 32;
//    const int thresholds [0:NUM_CHANNEL-1] = '{
//            48, 48, 48, 48, 48, 48, 48, 48,
//            48, 48, 48, 48, 48, 48, 48, 48, 
//            48, 48, 48, 48, 48, 48, 48, 48, 
//            48, 48, 48, 48, 48, 48, 48, 48, 
//            48, 48, 48, 48, 48, 48, 48, 48, 
//            48, 48, 48, 48, 48, 48, 48, 48, 
//            48, 48, 48, 48, 48, 48, 48, 48, 
//            48, 48, 48, 48, 48, 48, 48, 48
//        };
    const int thresholds [NUM_CHANNEL-1:0] = '{
            2, 33, 33, 34, 35, 36, 37, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 54, 55, 56, 57, 59, 60, 61, 63, 64
        };

endpackage