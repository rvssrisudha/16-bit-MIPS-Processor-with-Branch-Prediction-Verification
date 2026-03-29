// ============================================================
//  runfile.f    VCS filelist for MIPS BPU project
//
//  Usage:
//    vcs -f runfile.f [options]
//
//  See run_sim.sh for the full step-by-step flow.
//
//  File layout assumed (relative to project root):
//    Processor/    all RTL .v and .sv files
//    src/          all UVM .sv files
//    Instructions/ instruction memory hex files
// ============================================================

// ============================================================
//  Compiler switches
// ============================================================
-sverilog
-timescale=1ns/1ps
+v2k
-debug_all
+define+SIMULATION

// ============================================================
//  UVM library  (VCS built-in  no path needed if VCS >= 2014)
//  If your server needs an explicit path, replace with:
//    -ntb_opts uvm-1.2
//  or set UVM_HOME and use:
//    -f $UVM_HOME/src/uvm.f
// ============================================================
-ntb_opts uvm-1.2

// ============================================================
//  Include directories
//  Tells VCS where to find `include'd files
// ============================================================
+incdir+./Processor
+incdir+./src

// ============================================================
//  RTL sources   Processor/
//  Order: leaf modules first, top-level last
// ============================================================

// Arithmetic primitives
./Processor/halfadder.v
./Processor/full_adder.v
./Processor/Adder.v
./Processor/adder_internal.v
./Processor/wallace_8bit.v

// Datapath primitives
./Processor/mux2_1_1bit.v
./Processor/mux4_1_16bit.v
./Processor/comp.v

// Functional units
./Processor/ALU.v
./Processor/reg_file.v
./Processor/Control_Unit.v
./Processor/data_mem.v
./Processor/inst_mem.v

// [BPU] New modules added for branch predictor project
./Processor/bpu.sv
./Processor/perf_counters.sv

// Top-level processor (modified  BPU integrated)
./Processor/Main_Processor.v

// ============================================================
//  UVM Testbench sources   src/
//  processor_interface and top must come after the DUT
// ============================================================
./src/processor_interface.sv
./src/top.sv
