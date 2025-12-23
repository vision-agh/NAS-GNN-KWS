package nas_pkg;


    parameter F_RADIUS   = 10; //Search radius will be F_RADIUS*SKIPSTEPS                    
    parameter T_RADIUS_LOW   = 2000;
    parameter T_RADIUS_HIGH = 10000;           
    parameter SKIP_STEP = 2;        
    parameter MAX_EDGES  = (F_RADIUS*2) + 1; //the same F neighbour possible!;         
    parameter PRECISION_GEN  = 8;                    
    parameter PRECISION_CONV1  = 8;                    
    parameter PRECISION_CONV2  = 8;                    
    parameter PRECISION_CONV3  = 8;                    
    parameter PRECISION_CONV4  = 8;                    
    parameter CLS_NUM = 20;

    parameter T_WIDTH  = 32; //Max of 1000000
    parameter T_DIFF_WIDTH  = 15; //Max of 20000
    parameter F_WIDTH  = 7; //Max of 64

    parameter NUM_CHANNEL = 128;

    parameter INPUT_PARAMETER = 2; 
    parameter INPUT_DIM_1 = 2; 
    parameter OUTPUT_DIM_1 = 72;
    parameter OUTPUT_DIM_2 = 72;
    parameter OUTPUT_DIM_3 = 72;
    parameter OUTPUT_DIM_4 = 72;

    parameter ZERO_POINT = '0;
    parameter MULTIPLIER = '0;

      typedef struct packed {
      logic [T_WIDTH -1: 0] t;
      logic [F_WIDTH -1: 0] f;
      logic                 valid;
    } event_type;

    typedef struct packed {
      logic [T_DIFF_WIDTH-1 : 0] dt;
      logic                      is_connected;
    } edge_type;

    parameter DELTA_T_WIDTH = 15; //max value of 20000
    parameter GEN_MULTIPLIER_T = 941192;
    parameter [63:0] GEN_MULTIPLIER_F = 64'd7353064819; // (add 2^32)
    parameter GEN_ZERO_POINT = 34;

    parameter THROUGHPUT = 20; // for FIFO read
    // LIF parameters
    parameter DECAY_SHIFT = 8;
    parameter WEIGHT = 32;
    const int thresholds [0:NUM_CHANNEL-1] = '{
            64, 64, 63, 63, 63, 62, 62, 62, 61, 61, 61, 60, 60, 60, 59, 59, 
            59, 58, 58, 58, 57, 57, 57, 56, 56, 56, 56, 55, 55, 55, 54, 54, 
            54, 53, 53, 53, 53, 52, 52, 52, 51, 51, 51, 51, 50, 50, 50, 50, 
            49, 49, 49, 48, 48, 48, 48, 47, 47, 47, 47, 46, 46, 46, 46, 45, 
            45, 45, 45, 44, 44, 44, 44, 43, 43, 43, 43, 43, 42, 42, 42, 42, 
            41, 41, 41, 41, 40, 40, 40, 40, 40, 39, 39, 39, 39, 39, 38, 38, 
            38, 38, 37, 37, 37, 37, 37, 36, 36, 36, 36, 36, 35, 35, 35, 35, 
            35, 35, 34, 34, 34, 34, 34, 33, 33, 33, 33, 33, 33, 32, 32, 32
        };

endpackage