// ============================================================
//  bpu.sv    Branch Prediction Unit  (parameterized)
//  For MIPS-Processor-Verification-UVM project
//
//  Parameters:
//    NUM_ENTRIES : BTB/BHT table size  (4 or 8 recommended)
//                 Must be a power of 2
//    PC_WIDTH    : Processor PC width  (8 for this project)
//
//  Derived (do not override):
//    IDX_WIDTH   : $clog2(NUM_ENTRIES)
//    TAG_WIDTH   : PC_WIDTH - IDX_WIDTH
//
//  Address map (8-bit PC, 4 entries):
//    pc[1:0]  = index (2 bits)    pc[7:2]  = tag (6 bits)
//
//  Address map (8-bit PC, 8 entries):
//    pc[2:0]  = index (3 bits)    pc[7:3]  = tag (5 bits)
//
//  BTB per entry  : valid(1) + tag(TAG_WIDTH) + target(PC_WIDTH)
//  BHT per entry  : 2-bit saturating counter
//    11 = Strongly Taken      -> predict taken
//    10 = Weakly Taken        -> predict taken
//    01 = Weakly Not-Taken    -> predict not-taken  (reset default)
//    00 = Strongly Not-Taken  -> predict not-taken
//
//  Prediction  : BTB hit AND bht >= 2'b10
//  BTB update  : on every taken resolution
//  BHT update  : increment on taken, decrement on not-taken (saturating)
// ============================================================

`timescale 1ns/1ps

module bpu #(
    parameter int NUM_ENTRIES = 4,
    parameter int PC_WIDTH    = 8,

    // derived  do not override
    parameter int IDX_WIDTH   = $clog2(NUM_ENTRIES),
    parameter int TAG_WIDTH   = PC_WIDTH - IDX_WIDTH
)(
    input  logic                  clk,
    input  logic                  rst,

    // --- Fetch-time lookup (combinational) ---
    input  logic [PC_WIDTH-1:0]   fetch_pc,

    // --- Resolve inputs from decode stage ---
    input  logic                  resolve_en,
    input  logic [PC_WIDTH-1:0]   resolve_pc,
    input  logic                  resolve_taken,
    input  logic [PC_WIDTH-1:0]   resolve_target,

    // --- Prediction outputs (combinational) ---
    output logic                  pred_valid,    // BTB hit this cycle
    output logic                  pred_taken,    // predict taken
    output logic [PC_WIDTH-1:0]   pred_target,   // predicted target address

    // --- Observation outputs for UVM monitor / perf counters ---
    output logic                  btb_hit,
    output logic [1:0]            bht_state_out, // BHT counter at fetch index
    output logic                  mispredicted,  // resolve revealed wrong prediction
    output logic                  update_en      // BTB/BHT update firing this cycle
);

    // --------------------------------------------------------
    //  Storage arrays
    // --------------------------------------------------------
    logic                  btb_valid  [NUM_ENTRIES];
    logic [TAG_WIDTH-1:0]  btb_tag    [NUM_ENTRIES];
    logic [PC_WIDTH-1:0]   btb_target [NUM_ENTRIES];
    logic [1:0]            bht        [NUM_ENTRIES];

    // --------------------------------------------------------
    //  Index / tag extraction
    // --------------------------------------------------------
    logic [IDX_WIDTH-1:0]  fetch_idx,  resolve_idx;
    logic [TAG_WIDTH-1:0]  fetch_tag,  resolve_tag;

    assign fetch_idx   = fetch_pc  [IDX_WIDTH-1:0];
    assign fetch_tag   = fetch_pc  [PC_WIDTH-1:IDX_WIDTH];
    assign resolve_idx = resolve_pc[IDX_WIDTH-1:0];
    assign resolve_tag = resolve_pc[PC_WIDTH-1:IDX_WIDTH];

    // --------------------------------------------------------
    //  Combinational lookup  prediction at fetch time
    // --------------------------------------------------------
    logic btb_tag_match;

    assign btb_tag_match  = btb_valid[fetch_idx] &&
                            (btb_tag[fetch_idx] == fetch_tag);

    assign btb_hit        = btb_tag_match;
    assign bht_state_out  = bht[fetch_idx];
    assign pred_valid     = btb_tag_match;
    assign pred_taken     = btb_tag_match && (bht[fetch_idx] >= 2'b10);
    assign pred_target    = btb_target[fetch_idx];

    // --------------------------------------------------------
    //  Misprediction detection (combinational, at resolve time)
    //
    //  Fires when:
    //    (a) predicted taken  but jump was NOT taken, OR
    //    (b) predicted not-taken but jump WAS taken,  OR
    //    (c) predicted taken to the WRONG target
    // --------------------------------------------------------
    logic                pred_taken_at_resolve;
    logic [PC_WIDTH-1:0] pred_target_at_resolve;

    assign pred_taken_at_resolve  = btb_valid[resolve_idx]                &&
                                    (btb_tag[resolve_idx] == resolve_tag)  &&
                                    (bht[resolve_idx] >= 2'b10);

    assign pred_target_at_resolve = btb_target[resolve_idx];

    assign mispredicted = resolve_en && (
        (pred_taken_at_resolve  != resolve_taken)        ||
        (pred_taken_at_resolve  && resolve_taken         &&
         pred_target_at_resolve != resolve_target)
    );

    assign update_en = resolve_en;

    // --------------------------------------------------------
    //  Sequential update  BTB and BHT on clock edge
    // --------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                btb_valid [i] <= 1'b0;
                btb_tag   [i] <= '0;
                btb_target[i] <= '0;
                bht       [i] <= 2'b01;   // reset to Weakly Not-Taken
            end
        end
        else if (resolve_en) begin

            // --- BTB update: only write on taken jumps ---
            // (not-taken jumps have no useful target to store)
            if (resolve_taken) begin
                btb_valid [resolve_idx] <= 1'b1;
                btb_tag   [resolve_idx] <= resolve_tag;
                btb_target[resolve_idx] <= resolve_target;
            end

            // --- BHT update: 2-bit saturating counter ---
            if (resolve_taken)
                bht[resolve_idx] <= (bht[resolve_idx] == 2'b11) ?
                                     2'b11 :
                                     bht[resolve_idx] + 1'b1;
            else
                bht[resolve_idx] <= (bht[resolve_idx] == 2'b00) ?
                                     2'b00 :
                                     bht[resolve_idx] - 1'b1;
        end
    end

    // --------------------------------------------------------
    //  Simulation-only assertions
    // --------------------------------------------------------
`ifdef SIMULATION

    // BHT must never increment past 11
    property bht_no_overflow;
        @(posedge clk) disable iff (rst)
        (resolve_en && resolve_taken && (bht[resolve_idx] == 2'b11))
        |=> (bht[resolve_idx] == 2'b11);
    endproperty
    assert property (bht_no_overflow)
        else $error("BPU ASSERT: BHT overflowed past 2'b11 at idx=%0d",
                    resolve_idx);

    // BHT must never decrement past 00
    property bht_no_underflow;
        @(posedge clk) disable iff (rst)
        (resolve_en && !resolve_taken && (bht[resolve_idx] == 2'b00))
        |=> (bht[resolve_idx] == 2'b00);
    endproperty
    assert property (bht_no_underflow)
        else $error("BPU ASSERT: BHT underflowed past 2'b00 at idx=%0d",
                    resolve_idx);

    // BTB target must be consistent immediately after a taken update.
    // Guard with !$isunknown to skip X-state during initialisation.
    property btb_target_consistent;
        @(posedge clk) disable iff (rst)
        ($past(resolve_en) && $past(resolve_taken) &&
         !$isunknown($past(resolve_idx)) &&
         !$isunknown($past(resolve_target)))
        |-> (btb_target[$past(resolve_idx)] == $past(resolve_target));
    endproperty
    assert property (btb_target_consistent)
        else $error("BPU ASSERT: BTB target inconsistent after update idx=%0d",
                    $past(resolve_idx));

    // pred_taken must only be high when there is a BTB hit
    property pred_needs_btb_hit;
        @(posedge clk) disable iff (rst)
        pred_taken |-> btb_hit;
    endproperty
    assert property (pred_needs_btb_hit)
        else $error("BPU ASSERT: pred_taken high without BTB hit");

`endif

endmodule
