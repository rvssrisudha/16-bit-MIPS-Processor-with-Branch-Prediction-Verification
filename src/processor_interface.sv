interface processor_interface(input clk);

  // PC and Instruction word
  logic [7:0]  pc;
  logic [15:0] inst_out;
  logic [15:0] inst_in;

  // Register file signals
  logic [15:0] reg_data;
  logic [1:0]  reg_en;
  logic [2:0]  reg_add;

  // Data memory signals
  logic [15:0] mem_data;
  logic        mem_en;
  logic [2:0]  mem_add;

  // [BPU] Branch predictor observation signals
  logic        pred_taken;    // BPU predicted taken this fetch
  logic        pred_target;   // BPU had a valid target (BTB hit)
  logic        actual_taken;  // jump actually resolved as taken
  logic        flush;         // flush fired (misprediction kill)
  logic        mispredicted;  // misprediction detected this cycle
  logic        btb_hit;       // BTB hit at fetch
  logic [1:0]  bht_state;     // BHT counter value at fetch PC

  clocking driver_cb @ (negedge clk);
    output inst_in;
  endclocking : driver_cb

  clocking monitor_cb @ (negedge clk);
    input pc;
    input inst_out;
    input reg_data;
    input reg_en;
    input reg_add;
    input mem_data;
    input mem_en;
    input mem_add;
    // [BPU] monitor observes all branch signals
    input pred_taken;
    input pred_target;
    input actual_taken;
    input flush;
    input mispredicted;
    input btb_hit;
    input bht_state;
  endclocking : monitor_cb

  modport driver_if_mp  (clocking driver_cb);
  modport monitor_if_mp (clocking monitor_cb);

endinterface
