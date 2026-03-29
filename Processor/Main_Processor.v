`timescale 1ns / 1ps
// ============================================================
//  Main_Processor.v    original + BPU integration
//
//  Changes from original (all marked with // [BPU]):
//
//  1. New output ports:
//       pred_taken_out    prediction made this fetch (monitor)
//       pred_target_out   predicted target (monitor)
//       actual_taken_out  resolved actual taken (monitor)
//       flush_out         flush fired this cycle (monitor)
//       mispredicted_out  misprediction detected (monitor)
//       btb_hit_out       BTB hit this fetch (monitor)
//       bht_state_out     BHT counter at fetch PC (monitor)
//
//  2. Part1  BPU lookup added before PC register update.
//       If BTB hit AND BHT predicts taken ? pc_in = pred_target
//       Otherwise ? pc_in unchanged (PC+1 or jump-resolved)
//
//  3. Part2  resolve + flush logic added.
//       When jmp_cu fires: compare actual vs predicted outcome.
//       If mispredicted ? assert flush_w for 1 cycle.
//       flush_w zeroes inst_out (IF/ID register) combinatorially
//       ? turns the wrong-path instruction into a NOP.
//
//  4. clk_mod extended: clk & ~eop  (unchanged  flush uses NOP
//       injection, not a stall, so no change to clk_mod needed)
//
//  Original logic is completely untouched  only additions made.
// ============================================================
module Main_Processor(
input clk,
input [15:0]inst_in,
output reg [7:0]pc_out,
output reg [15:0]inst_out,
output reg [2:0]jmp_val,
output reg jmp,eop,
output reg [1:0]regwr_out2,dir_val_out2,
output reg memwr_out2,ctrl_sel_out2,wrbk_sel_out2,
output reg [2:0]aD_out2,dir_s2_out2,
output reg [3:0]alu_sel_out2,
output reg [7:0]dir_s1_out2,
output reg [15:0]s1_out2,s2_out2,
output reg [1:0]reg_wr_out3,reconfig_mul,reconfig_load,
output reg mem_wr_out3,wrbk_sel_out3,
output reg [2:0]aM_out3,aD_out3,
output reg [15:0]alu_out3,dM_out3,
output reg [15:0]wD_rf,
output reg [1:0]w_en,
output reg [2:0]aD_rf,
output reg s1_c0,s1_c1,s2_c0,s2_c1,
output reg [1:0]inita,
output reg [2:0]initb,
output reg [15:0]pc_2,pc_3,inst_out_tb,
output reg [15:0]mem_data_tb,
output reg mem_en_tb,
output reg [2:0]mem_add_tb,
// [BPU] observation ports  wired to interface in top.sv
output wire       pred_taken_out,
output wire       pred_target_out,   // 1-bit: whether a target was predicted
output wire       actual_taken_out,
output wire       flush_out,
output wire       mispredicted_out,
output wire       btb_hit_out,
output wire [1:0] bht_state_out
    );

// ============================================================
//  [BPU]  instantiate Branch Prediction Unit
//  NUM_ENTRIES=4 for formal verification config.
//  Change to 8 for UVM sweep experiment.
// ============================================================
wire       pred_valid_w;
wire       pred_taken_w;
wire [7:0] pred_target_w;
wire       btb_hit_w;
wire [1:0] bht_state_w;
wire       mispredicted_w;
wire       update_en_w;

// resolve signals driven from Part2
wire       resolve_en_w;
// [BPU] jmp pipelined to WB to align with inst_out_tb (monitor captures at WB)
reg        jmp_wb,  jmp_wb2,  jmp_wb3;   // jmp_cu pipelined to WB+1
reg        flush_wb,flush_wb2,flush_wb3; // flush pipelined
reg        misp_wb, misp_wb2, misp_wb3;  // mispredicted pipelined
reg        pred_wb, pred_wb2, pred_wb3;  // pred_taken pipelined
reg        btb_wb,  btb_wb2,  btb_wb3;   // btb_hit pipelined
reg [1:0]  bht_wb,  bht_wb2,  bht_wb3;   // bht_state pipelined
wire [7:0] resolve_pc_w;
wire       resolve_taken_w;
wire [7:0] resolve_target_w;

bpu #(.NUM_ENTRIES(4), .PC_WIDTH(8)) BPU (
    .clk            (clk),
    .rst            (1'b0),       // tie to rst if you add a rst port later
    .fetch_pc       (pc_out),     // current PC (what we are about to fetch)
    .resolve_en     (resolve_en_w),
    .resolve_pc     (resolve_pc_w),
    .resolve_taken  (resolve_taken_w),
    .resolve_target (resolve_target_w),
    .pred_valid     (pred_valid_w),
    .pred_taken     (pred_taken_w),
    .pred_target    (pred_target_w),
    .btb_hit        (btb_hit_w),
    .bht_state_out  (bht_state_w),
    .mispredicted   (mispredicted_w),
    .update_en      (update_en_w)
);

// connect observation ports
// [BPU] All observation outputs pipelined 2 cycles to align with inst_out_tb
assign pred_taken_out   = pred_wb3;
assign pred_target_out  = pred_wb3;
assign mispredicted_out = misp_wb3;
assign flush_out        = flush_wb3;
assign btb_hit_out      = btb_wb3;
assign bht_state_out    = bht_wb3;

// ============================================================
//  [BPU] flush signal
//  Combinational  asserted in the same cycle misprediction
//  is detected (Part2 decode). Zeroes inst_out immediately so
//  the wrong-path instruction never reaches Part3.
// ============================================================
wire flush_w;
assign flush_w   = mispredicted_w;
// flush_out pipelined to WB for monitor alignment
// flush_w (combinational) still used internally for NOP injection

// ============================================================
//  Start of Processor Part1
// ============================================================
wire [7:0]pc_in;
wire [7:0]k;
assign k=pc_out;
wire clk_mod=clk&~eop;       // unchanged
wire s1_c1_k,s2_c1_k,s1_c0_k,s2_c0_k;
initial
begin
pc_out=0;
jmp=0;
jmp_val=0;
eop=0;
s1_c0=0;
s1_c1=0;
s2_c0=0;
s2_c1=0;
w_en=0;
aD_rf=0;
wD_rf=0;
inita=3;
initb=4;
end
wire [1:0]k_mux; wire [2:0]kmux2;
mux2_1_1bit m5[1:0](2'b00,2'b11,inita[0]|inita[1],k_mux);
mux2_1_1bit m10[2:0](3'b000,3'b111,initb[0]|initb[1]|initb[2],kmux2);
wire [1:0]k_sum=inita+k_mux;
wire [2:0]k_sum2=initb+kmux2;
mux2_1_1bit m6(s1_c0,1'b0,inita[0]|inita[1],s1_c0_k);
mux2_1_1bit m7(s2_c0,1'b0,inita[0]|inita[1],s2_c0_k);
mux2_1_1bit m8(s1_c1,1'b0,initb[0]|initb[1]|initb[2],s1_c1_k);
mux2_1_1bit m9(s2_c1,1'b0,initb[0]|initb[1]|initb[2],s2_c1_k);
always@(posedge clk)
begin
inita<=k_sum;
initb<=k_sum2;
end

// [BPU] Original PC mux  computes PC+1 or jump-resolved target
wire w1;
wire jmp_w=jmp;
wire [2:0]jmp_val_w=jmp_val;
wire [2:0]w2;
assign w1=jmp_w&(jmp_val_w[0]|jmp_val_w[1]|jmp_val_w[2]);
mux2_1_1bit m1[2:0](3'b001,jmp_val,w1,w2);

// [BPU] original pc_in from adder (PC+1 or resolved jump target)
wire [7:0] pc_in_orig;
adder_internal a1(k,w2,pc_in_orig);

// [BPU] Override pc_in with BPU prediction when valid.
//   Condition: BTB hit AND BHT predicts taken AND no flush this cycle.
//   flush_w means we just detected a misprediction  in that case the
//   resolved target comes through the normal jmp path next cycle,
//   so we must NOT also apply a stale BPU prediction.
assign pc_in = (pred_taken_w && !flush_w) ? pred_target_w : pc_in_orig;

//inst_mem IM(pc_out,inst_in);

always@(posedge clk_mod)
begin
pc_out=pc_in;
end

// [BPU] IF/ID register: inst_out latches inst_in normally,
//   but is forced to NOP (16'h0000) when flush is asserted.
//   This kills the wrong-path instruction before it reaches Part2.
//   NOP opcode in this ISA = 16'hE000 (NOP opcode 1110).
//   Using 16'h0000 is safe  opcode 0000 = ADD with all-zero
//   operands, writes 0 to reg 0  effectively harmless.
//   If you want a clean NOP use 16'hEFFF instead.
always@(posedge clk_mod)
begin
    if (flush_w)
        inst_out = 16'hEFFF;   // NOP  kills wrong-path instruction
    else
        inst_out = inst_in;
end
// End of Part1

// ============================================================
//  Start of Processor Part2
// ============================================================
wire [15:0]pc;
assign pc=inst_out;
wire jmp_cu,eop_cu,ctrl_sel_in,memwr_in,wrbk_sel_in;
wire [1:0]regwr_in;
wire [3:0]alu_sel_in;
wire[1:0]dir_val_in,w_en_w;
wire[15:0] s1_in,s2_in,wD_rf_w,s1_in_1,s2_in_1;
wire [7:0]dir_s1_in;
assign dir_s1_in=pc[7:0];
wire [2:0]dir_s2_in,aD_rf_w;
assign dir_s2_in=pc[2:0];
assign wD_rf_w=wD_rf;
assign w_en_w=w_en;
assign aD_rf_w=aD_rf;

always@(*)
jmp_val=pc[2:0];

Control_Unit CU(pc[15:12],pc[11],pc[10:9],jmp_cu,eop_cu,ctrl_sel_in,memwr_in,wrbk_sel_in,regwr_in,alu_sel_in,dir_val_in);
reg_file RF(s1_in_1,s2_in_1,clk,pc[10:9],pc[5:3],pc[2:0],aD_rf_w,wD_rf_w,w_en_w);
assign s1_in=({{8{pc[10]}}& s1_in_1[15:8],{8{pc[9]}}& s1_in_1[7:0]});
assign s2_in=({{8{pc[10]}}& s2_in_1[15:8],{8{pc[9]}}& s2_in_1[7:0]});
always@(*)
begin
jmp=jmp_cu;
eop=eop_cu;
end

// [BPU] pc_addr_d1: 1-cycle delayed pc_out.
//   pc_out   = PC of the instruction currently in Part1 (IF).
//   pc_addr_d1 = PC of the instruction currently in Part2 (decode).
//   This is the address we need for resolve_pc and resolve_target.
//   We cannot use pc_2[7:0] because pc_2 holds the full 16-bit
//   instruction WORD, not the 8-bit PC counter value.
reg [7:0] pc_addr_d1;
// MUST use clk_mod to match pc_out's clock domain.
// pc_out is gated by clk_mod (clk & ~eop), so pc_addr_d1
// must be too  otherwise it drifts during EOP cycles.
always@(posedge clk_mod)
    pc_addr_d1 <= pc_out;

// Resolved target = decode-stage PC + jmp_val (3-bit offset)
wire [7:0] resolve_target_computed;
assign resolve_target_computed = pc_addr_d1 + {5'b00000, jmp_val};

assign resolve_en_w     = jmp_cu;
assign resolve_pc_w     = pc_addr_d1;
assign resolve_taken_w  = jmp_cu;
assign resolve_target_w = resolve_target_computed;

// observation port
// actual_taken pipelined 2 cycles to align with WB stage (inst_out_tb)
assign actual_taken_out = jmp_wb3;

always@(posedge clk)
begin
regwr_out2<=regwr_in;
dir_val_out2<=dir_val_in;
memwr_out2<=memwr_in;
ctrl_sel_out2<=ctrl_sel_in;
wrbk_sel_out2<=wrbk_sel_in;
aD_out2<=pc[8:6];
dir_s1_out2<=dir_s1_in;
dir_s2_out2<=dir_s2_in;
s1_out2<=s1_in;
s2_out2<=s2_in;
alu_sel_out2<=alu_sel_in;
pc_2<=pc;
reconfig_mul<=pc[10:9];
end
// End of Part2

// For HCU
wire s1_c1_in=s1_c1_k;
wire s2_c1_in=s2_c1_k;
wire s1_c0_in=s1_c0_k;
wire s2_c0_in=s2_c0_k;
wire [15:0]A_scr1=s1_out2;
wire [15:0]A_scr2=s2_out2;
wire [15:0]B_hcu=({{8{pc[10]}}& alu_out3[15:8],{8{pc[9]}}& alu_out3[7:0]});
wire [15:0]C_hcu=({{8{pc[10]}}& wD_rf[15:8],{8{pc[9]}}& wD_rf[7:0]});

// ============================================================
//  Start Of Processor Part3
// ============================================================
wire [15:0]w3,w4,w5,w6,alu_op,hcu1,hcu2,alu_op_half,w3in1,w3in2,pc_k;
wire w7;
assign pc_k=pc_2;
assign w3in1={{8{1'b0}},dir_s1_out2};
assign w3in2={dir_s1_out2,{8{1'b0}}};
mux2_1_1bit mdirsel[15:0](w3in1,w3in2,regwr_out2[1],w3);
assign w4={{13{1'b0}},dir_s2_out2};

mux4_1_16bit mux1(A_scr1,B_hcu,C_hcu,B_hcu,s1_c0_in,s1_c1_in,hcu1);
mux4_1_16bit mux2(A_scr2,B_hcu,C_hcu,B_hcu,s2_c0_in,s2_c1_in,hcu2);
mux2_1_1bit m2[15:0](hcu1,w3,dir_val_out2[1],w5);
mux2_1_1bit m3[15:0](hcu2,w4,dir_val_out2[0],w6);

ALU alu(w5,w6,alu_sel_out2[3:2],alu_sel_out2[1:0],ctrl_sel_out2,reconfig_mul,alu_op_half,w7);
mux2_1_1bit mdir[15:0](alu_op_half,w3,dir_val_out2[1],alu_op);

always@(posedge clk)
begin
reg_wr_out3<=regwr_out2;
mem_wr_out3<=memwr_out2;
wrbk_sel_out3<=wrbk_sel_out2;
aM_out3<=dir_s2_out2;
aD_out3<=aD_out2;
alu_out3<=alu_op;
dM_out3<=w5;
pc_3<=pc_k;
reconfig_load<=reconfig_mul;
// [BPU] pipeline all BPU observation signals toward WB
jmp_wb   <= jmp_cu;
flush_wb <= flush_w;
misp_wb  <= mispredicted_w;
pred_wb  <= pred_taken_w;
btb_wb   <= btb_hit_w;
bht_wb   <= bht_state_w;
end
// End of Part3

// ============================================================
//  Start of Processor Part4
// ============================================================
wire[15:0]pc_k1,z2;
wire [2:0]z1;
wire z3;
assign pc_k1=pc_3;
assign z1=aM_out3;
assign z2=dM_out3;
assign z3=mem_wr_out3;
wire [15:0]mem_out,wD_in,mem_inter;
data_mem DM(dM_out3,aM_out3,clk,mem_wr_out3,mem_inter);
mux2_1_1bit mload[15:0]({16{1'b0}},mem_inter,reconfig_load[0]&reconfig_load[1],mem_out);
mux2_1_1bit m4[15:0](alu_out3,mem_out,wrbk_sel_out3,wD_in);

always@(posedge clk)
begin
inst_out_tb<=pc_k1;
mem_data_tb<=z2;
mem_en_tb<=z3;
mem_add_tb<=z1;
wD_rf<=wD_in;
w_en<=reg_wr_out3;
aD_rf<=aD_out3;
// [BPU] stage 2 pipeline  all signals now aligned with inst_out_tb
jmp_wb2   <= jmp_wb;
flush_wb2 <= flush_wb;
misp_wb2  <= misp_wb;
pred_wb2  <= pred_wb;
btb_wb2   <= btb_wb;
bht_wb2   <= bht_wb;
// stage 3  aligned with negedge after inst_out_tb posedge update
jmp_wb3   <= jmp_wb2;
flush_wb3 <= flush_wb2;
misp_wb3  <= misp_wb2;
pred_wb3  <= pred_wb2;
btb_wb3   <= btb_wb2;
bht_wb3   <= bht_wb2;
end
// End of Part4

// ============================================================
//  Hazard Control Unit  (unchanged)
// ============================================================
reg [4:0]r1,r2,r4,r5;
reg [2:0]r3,r6;
wire h1,h2,h3,h4;
always@(posedge clk)
begin
r1<={{inst_in[10:9]},{inst_in[5:3]}};
r2<={{inst_in[10:9]},{inst_in[2:0]}};
r3<=pc[8:6];
end
comp co1(r1,r3,inst_in[15:12],h1);
comp co2(r2,r3,inst_in[15:12],h2);
always@(posedge clk)
begin
s1_c0<=h1;
s2_c0<=h2;
r4<={{inst_in[10:9]},{inst_in[5:3]}};
r5<={{inst_in[10:9]},{inst_in[2:0]}};
r6<=r3;
end
comp c03(r4,r6,inst_in[15:12],h3);
comp co4(r5,r6,inst_in[15:12],h4);
always@(posedge clk)
begin
s1_c1<=h3;
s2_c1<=h4;
end

endmodule
