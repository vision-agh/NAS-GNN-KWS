package nas_pkg;


    parameter F_RADIUS   = 10; //Search radius will be F_RADIUS*SKIPSTEPS                    
    parameter T_RADIUS   = 20000;         
    parameter SKIP_STEP = 1;        
    parameter MAX_EDGES  = (F_RADIUS*2) + 1; //the same F neighbour possible!;         
    parameter PRECISION_GEN  = 8;                    
    parameter PRECISION_CONV1  = 8;                    
    parameter PRECISION_CONV2  = 8;                    
    parameter PRECISION_CONV3  = 8;                    
    parameter PRECISION_CONV4  = 8;                    
    parameter CLS_NUM = 20;

    parameter T_WIDTH  = 32; //Max of 1000000
    parameter T_DIFF_WIDTH  = 15; //Max of 20000
    parameter F_WIDTH  = 7; //Max of 700

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
    parameter GEN_MULTIPLIER_T = 958724;
    parameter GEN_MULTIPLIER_F = 1369605345;
    parameter GEN_ZERO_POINT = 32;

endpackage