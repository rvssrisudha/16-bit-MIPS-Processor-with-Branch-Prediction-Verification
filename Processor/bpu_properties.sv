// ============================================================
//  bpu_properties.sv    SVA formal properties for bpu.sv
//
//  All properties use only bpu.sv internal/port signals.
//  Bound to bpu via SystemVerilog bind construct.
//
//  JasperGold run:
//    jg -batch -tcl jg_run.tcl
//
//  Properties:
//    P1 : flush (mispredicted) fires on every wrong prediction
//    P2 : no misprediction flagged on a correct prediction
//    P3 : BHT saturates  never overflows 11 or underflows 00
//    P4 : pred_taken only asserted when BTB hits
//    P5 : BTB target consistent after taken update
// ============================================================

`timescale 1ns/1ps

module bpu_properties #(
    parameter int NUM_ENTRIES = 4,
    parameter int PC_WIDTH    = 8,
    parameter int IDX_WIDTH   = $clog2(NUM_ENTRIES),
    parameter int TAG_WIDTH   = PC_WIDTH - IDX_WIDTH
)(
    input  logic                 clk,
    input  logic                 rst,
    // BPU ports
    input  logic [PC_WIDTH-1:0]  fetch_pc,
    input  logic                 resolve_en,
    input  logic [PC_WIDTH-1:0]  resolve_pc,
    input  logic                 resolve_taken,
    input  logic [PC_WIDTH-1:0]  resolve_target,
    input  logic                 pred_valid,
    input  logic                 pred_taken,
    input  logic [PC_WIDTH-1:0]  pred_target,
    input  logic                 mispredicted,
    input  logic                 update_en,
    // BPU internal arrays (accessed via hierarchical reference)
    input  logic [1:0]           bht_arr        [NUM_ENTRIES],
    input  logic                 btb_valid_arr  [NUM_ENTRIES],
    input  logic [TAG_WIDTH-1:0] btb_tag_arr    [NUM_ENTRIES],
    input  logic [PC_WIDTH-1:0]  btb_target_arr [NUM_ENTRIES]
);

    // Convenience
    logic [IDX_WIDTH-1:0] r_idx;
    assign r_idx = resolve_pc[IDX_WIDTH-1:0];

    // --------------------------------------------------------
    //  P1  mispredicted fires when resolve reveals direction error
    //  Uses resolve-time BTB/BHT state (same as RTL) to compute
    //  the expected misprediction value and compares against DUT.
    // --------------------------------------------------------
    logic pred_taken_at_res;
    assign pred_taken_at_res = btb_valid_arr[resolve_pc[IDX_WIDTH-1:0]] &&
                               (btb_tag_arr[resolve_pc[IDX_WIDTH-1:0]] ==
                                resolve_pc[PC_WIDTH-1:IDX_WIDTH]) &&
                               (bht_arr[resolve_pc[IDX_WIDTH-1:0]] >= 2'b10);

    property P1_mispredict_correct;
        @(posedge clk) disable iff (rst)
        resolve_en |->
            (mispredicted == (
                (pred_taken_at_res != resolve_taken) ||
                (pred_taken_at_res && resolve_taken &&
                 btb_target_arr[resolve_pc[IDX_WIDTH-1:0]] != resolve_target)
            ));
    endproperty
    P1: assert property (P1_mispredict_correct)
        else $error("P1 FAIL: mispredicted does not match expected value");

    // --------------------------------------------------------
    //  P2  mispredicted=0 when no resolve in flight
    // --------------------------------------------------------
    property P2_no_mispredict_without_resolve;
        @(posedge clk) disable iff (rst)
        !resolve_en |-> !mispredicted;
    endproperty
    P2: assert property (P2_no_mispredict_without_resolve)
        else $error("P2 FAIL: mispredicted asserted without resolve_en");

    // --------------------------------------------------------
    //  P3  BHT 2-bit saturating counter bounds
    // --------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < NUM_ENTRIES; gi++) begin : gen_sat

            property P3_no_overflow;
                @(posedge clk) disable iff (rst)
                (resolve_en && resolve_taken &&
                 resolve_pc[IDX_WIDTH-1:0] == gi[IDX_WIDTH-1:0] &&
                 bht_arr[gi] == 2'b11)
                |=> (bht_arr[gi] == 2'b11);
            endproperty
            P3_ovf: assert property (P3_no_overflow)
                else $error("P3 FAIL: BHT[%0d] overflowed", gi);

            property P3_no_underflow;
                @(posedge clk) disable iff (rst)
                (resolve_en && !resolve_taken &&
                 resolve_pc[IDX_WIDTH-1:0] == gi[IDX_WIDTH-1:0] &&
                 bht_arr[gi] == 2'b00)
                |=> (bht_arr[gi] == 2'b00);
            endproperty
            P3_udf: assert property (P3_no_underflow)
                else $error("P3 FAIL: BHT[%0d] underflowed", gi);

        end
    endgenerate

    // --------------------------------------------------------
    //  P4  pred_taken requires a BTB hit
    //  Cannot predict a target we don't have stored
    // --------------------------------------------------------
    property P4_pred_needs_btb_hit;
        @(posedge clk) disable iff (rst)
        pred_taken |-> pred_valid;
    endproperty
    P4: assert property (P4_pred_needs_btb_hit)
        else $error("P4 FAIL: pred_taken high without BTB hit");

    // --------------------------------------------------------
    //  P5  BTB target consistent after taken update
    // --------------------------------------------------------
    property P5_btb_consistent;
        @(posedge clk) disable iff (rst)
        // BTB update uses non-blocking assignment  visible one cycle after
        // resolve fires. Use |=> to check the cycle AFTER the update.
        (resolve_en && resolve_taken &&
         !$isunknown(resolve_pc) &&
         !$isunknown(resolve_target))
        |=> (btb_target_arr[$past(resolve_pc[IDX_WIDTH-1:0])] ==
             $past(resolve_target));
    endproperty
    P5: assert property (P5_btb_consistent)
        else $error("P5 FAIL: BTB target mismatch after update");

    // --------------------------------------------------------
    //  Cover points  help JasperGold reach interesting states
    // --------------------------------------------------------
    cover property (@(posedge clk) disable iff (rst)
        mispredicted);
    cover property (@(posedge clk) disable iff (rst)
        resolve_en && resolve_taken && !mispredicted);
    cover property (@(posedge clk) disable iff (rst)
        pred_taken && resolve_taken);
    cover property (@(posedge clk) disable iff (rst)
        resolve_en && bht_arr[r_idx] == 2'b11);
    cover property (@(posedge clk) disable iff (rst)
        resolve_en && bht_arr[r_idx] == 2'b00);

endmodule

// ============================================================
//  Bind  attach to bpu instance
// ============================================================
bind bpu bpu_properties #(
    .NUM_ENTRIES (NUM_ENTRIES),
    .PC_WIDTH    (PC_WIDTH),
    .IDX_WIDTH   (IDX_WIDTH),
    .TAG_WIDTH   (TAG_WIDTH)
) bpu_props_inst (
    .clk            (clk),
    .rst            (rst),
    .fetch_pc       (fetch_pc),
    .resolve_en     (resolve_en),
    .resolve_pc     (resolve_pc),
    .resolve_taken  (resolve_taken),
    .resolve_target (resolve_target),
    .pred_valid     (pred_valid),
    .pred_taken     (pred_taken),
    .pred_target    (pred_target),
    .mispredicted   (mispredicted),
    .update_en      (update_en),
    .bht_arr        (bht),
    .btb_valid_arr  (btb_valid),
    .btb_tag_arr    (btb_tag),
    .btb_target_arr (btb_target)
);
