class processor_subscriber extends uvm_subscriber #(processor_transaction);
//Register subscriber in uvm factory
`uvm_component_utils(processor_subscriber)
//Define variables to store read/write request and address

bit [15:0] instruction;
// [BPU] branch prediction fields sampled from monitor
bit        pred_taken;
bit        actual_taken;
bit        btb_hit;
bit        flush;
bit [1:0]  bht_state;
//Define covergroup and coverpoints
// Branch prediction coverage
covergroup cover_branch;
   // All 4 BHT states must be visited
   cp_bht_state: coverpoint bht_state {
      bins strongly_taken    = {2'b11};
      bins weakly_taken      = {2'b10};
      bins weakly_not_taken  = {2'b01};
      bins strongly_not_taken= {2'b00};
   }
   // All 4 prediction outcomes (TP/TN/FP/FN)
   cp_pred_outcome: coverpoint {pred_taken, actual_taken} {
      bins true_positive  = {2'b11};   // predicted taken, was taken
      bins true_negative  = {2'b00};   // predicted not-taken, not taken
      bins false_positive = {2'b10};   // predicted taken, not taken (mispredict)
      bins false_negative = {2'b01};   // predicted not-taken, was taken (mispredict)
   }
   // BTB hit/miss
   cp_btb: coverpoint btb_hit {
      bins hit  = {1'b1};
      bins miss = {1'b0};
   }
   // Flush fired
   cp_flush: coverpoint flush {
      bins flushed     = {1'b1};
      bins not_flushed = {1'b0};
   }
endgroup

covergroup cover_processor;
coverpoint instruction
{

bins Addition = {[16'h0000:16'h0FFF]};
bins Subraction = {[16'h1000:16'h1FFF]};
bins Increment = {[16'h3000:16'h3FFF]};
bins Decrement = {[16'h2000:16'h2FFF]};
bins AND_NAND = {[16'h4000:16'h4FFF]};
bins OR_NOR = {[16'h5000:16'h5FFF]};
bins EXOR_EXNOR = {[16'h6000:16'h6FFF]};
bins Buff_Inv = {[16'h7000:16'h7FFF]};
bins Multiplication = {[16'h8000:16'h8FFF]};
bins ShiftL_ShiftR = {[16'hC000:16'hCFFF]};
bins Load = {[16'hA000:16'hAFFF]};
bins Store = {[16'hB000:16'hBFFF]};
bins Move_MoveI = {[16'h9000:16'h9FFF]};
bins Jump = {[16'hD000:16'hDFFF]};
bins NOP = {[16'hE000:16'hEFFF]};
}
endgroup
//Declare virtual interface object
virtual processor_interface processor_vif;
//Declare analysis port to get transactions from monitor
uvm_analysis_imp #(processor_transaction,processor_subscriber) aport;


  function new (string name, uvm_component parent);
  begin
    super.new(name,parent);

    //Call new for covergroup
	cover_processor = new();
	cover_branch    = new();
  end
  endfunction

  function void build_phase(uvm_phase phase);
    // Get virtual interface reference from config database
if(!uvm_config_db#(virtual processor_interface)::get(this, "",
"processor_vif", processor_vif)) begin
`uvm_error("", "uvm_config_db::get failed")
end
    //Instantiate analysis port
aport = new("aport",this);
  endfunction 

  //Write function for the analysis port
function void write(processor_transaction t);
instruction   = t.inst_out;
pred_taken    = t.pred_taken;
actual_taken  = t.actual_taken;
btb_hit       = t.btb_hit;
flush         = t.flush;
bht_state     = t.bht_state;
cover_processor.sample();
cover_branch.sample();
endfunction
endclass
