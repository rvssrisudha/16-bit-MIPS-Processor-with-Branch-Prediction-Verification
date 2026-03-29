`include "uvm_macros.svh"
`include "processor_testbench_pkg.sv"

module top;
  import uvm_pkg::*;
  import processor_testbench_pkg::*;

  bit clk;

  // clock generation
  always #5 clk = ~clk;
  initial clk = 0;

  // Instantiate the interface
  processor_interface processor_if(clk);

  // Instantiate DUT
  Main_Processor dut(
    .inst_in         (processor_if.inst_in),
    .clk             (processor_if.clk),
    .pc_out          (processor_if.pc),
    .inst_out_tb     (processor_if.inst_out),
    .wD_rf           (processor_if.reg_data),
    .w_en            (processor_if.reg_en),
    .aD_rf           (processor_if.reg_add),
    .mem_data_tb     (processor_if.mem_data),
    .mem_en_tb       (processor_if.mem_en),
    .mem_add_tb      (processor_if.mem_add),
    // [BPU] observation ports
    .pred_taken_out  (processor_if.pred_taken),
    .pred_target_out (processor_if.pred_target),
    .actual_taken_out(processor_if.actual_taken),
    .flush_out       (processor_if.flush),
    .mispredicted_out(processor_if.mispredicted),
    .btb_hit_out     (processor_if.btb_hit),
    .bht_state_out   (processor_if.bht_state)
  );

  // [BPU] Instantiate performance counters
  // correct_pred: registered 1 cycle after resolve to avoid
  // combinational glitch where actual_taken and mispredicted
  // settle at slightly different times in the same delta cycle.
  logic correct_pred_r;
  always_ff @(posedge clk)
    correct_pred_r <= processor_if.actual_taken & ~processor_if.mispredicted;

  perf_counters perf (
    .clk          (clk),
    .rst          (1'b0),
    .resolve_en   (processor_if.actual_taken),
    .mispredicted (processor_if.mispredicted),
    .flush        (processor_if.flush),
    .correct_pred (correct_pred_r)
  );

  initial begin
    // Place the interface into the UVM configuration database
    uvm_config_db#(virtual processor_interface)::set(
        null, "*", "processor_vif", processor_if);

    // Start the test
    run_test();
  end

  initial begin
    $vcdpluson();
  end

endmodule
