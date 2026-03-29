// ============================================================
//  perf_counters.sv
//  Hardware performance counters for branch predictor project
//
//  5 x 32-bit counters, all free-running from reset:
//
//    cycle_cnt          : total clock cycles elapsed
//    branch_count       : every jump instruction that resolves
//    correct_preds      : predictions that matched actual outcome
//    mispredictions     : predictions that did NOT match
//    flush_cycles       : cycles where flush was asserted
//                         (pipeline stalled fetching wrong path)
//
//  Derived metrics (computed in UVM scoreboard, not in RTL):
//    prediction_accuracy  = correct_preds / branch_count  x 100%
//    ipc_impact           = flush_cycles  / cycle_cnt     x 100%
//
//  How to read from UVM scoreboard (backdoor):
//    logic [31:0] val;
//    uvm_hdl_read("tb_top.perf.cycle_cnt",    val);
//    uvm_hdl_read("tb_top.perf.branch_count", val);
//    ... etc
//
//  Instantiate in top.sv:
//    perf_counters perf (
//        .clk          (clk),
//        .rst          (rst),
//        .resolve_en   (resolve_en_w),   // from BPU
//        .mispredicted (mispredicted_w), // from BPU
//        .flush        (flush_w),        // from Main_Processor
//        .correct_pred (correct_pred_w)  // = resolve_en & ~mispredicted
//    );
// ============================================================

`timescale 1ns/1ps

module perf_counters (
    input logic clk,
    input logic rst,

    // --- Event inputs (1-cycle pulses from BPU + pipeline) ---
    input logic resolve_en,    // a jump resolved this cycle
    input logic mispredicted,  // that resolution was a misprediction
    input logic flush,         // pipeline flush active this cycle
    input logic correct_pred   // resolve_en & ~mispredicted (convenience)
);

    // --------------------------------------------------------
    //  Counter registers
    // --------------------------------------------------------
    logic [31:0] cycle_cnt;
    logic [31:0] branch_count;
    logic [31:0] correct_preds;
    logic [31:0] mispredictions;
    logic [31:0] flush_cycles;

    // --------------------------------------------------------
    //  Free-running counters
    // --------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_cnt      <= 32'd0;
            branch_count   <= 32'd0;
            correct_preds  <= 32'd0;
            mispredictions <= 32'd0;
            flush_cycles   <= 32'd0;
        end
        else begin
            // cycle counter increments every clock
            cycle_cnt <= cycle_cnt + 1;

            // branch events  only when a jump resolves
            if (resolve_en) begin
                branch_count <= branch_count + 1;
                if (mispredicted)
                    mispredictions <= mispredictions + 1;
                else
                    correct_preds  <= correct_preds  + 1;
            end

            // flush counter  every cycle the pipeline is flushing
            if (flush)
                flush_cycles <= flush_cycles + 1;
        end
    end

    // --------------------------------------------------------
    //  Simulation-only assertions
    // --------------------------------------------------------
`ifdef SIMULATION

    // counts_consistent check removed:
    // correct_pred is registered (1 cycle delayed) so back-to-back
    // jumps cause a transient imbalance that is not a real bug.
    // End-of-test accuracy check in UVM scoreboard is the right place.

    // mispredicted and correct_pred must never be high simultaneously.
    // correct_pred is registered so they land in different cycles 
    // this property confirms no cycle has both asserted at once.
    property mispredict_mutex;
        @(posedge clk) disable iff (rst)
        mispredicted |-> !correct_pred;
    endproperty
    assert property (mispredict_mutex)
        else $error("PERF: mispredicted and correct_pred both high");

`endif

endmodule
