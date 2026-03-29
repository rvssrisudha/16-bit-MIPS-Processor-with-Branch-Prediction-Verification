#!/bin/bash
# ============================================================
#  run_sim.sh    compile and simulate with VCS + UVM
#  Run from project root:  ./run_sim.sh
# ============================================================

set -e

# ---- Detect UVM_HOME if not already set ----
if [ -z "$UVM_HOME" ]; then
    for candidate in \
        /tools/uvm/uvm-1.2 \
        /cadence/uvm/uvm-1.2 \
        /synopsys/uvm/latest \
        $VCS_HOME/etc/uvm \
        $VCS_HOME/packages/uvm/latest \
        /usr/local/uvm
    do
        if [ -f "$candidate/src/uvm_macros.svh" ]; then
            export UVM_HOME="$candidate"
            echo "[run_sim] UVM found at: $UVM_HOME"
            break
        fi
    done
fi

if [ -z "$UVM_HOME" ]; then
    echo ""
    echo "ERROR: UVM not found. Set it manually:"
    echo "  export UVM_HOME=/path/to/uvm-1.2"
    echo "  ./run_sim.sh"
    echo ""
    echo "If on EDA Playground: see eda_playground_notes.txt"
    exit 1
fi

PROC_DIR="./Processor"
SRC_DIR="./src"

echo ""
echo "=== Compiling ==="

vcs -sverilog -full64 \
    +v2k \
    -timescale=1ns/1ps \
    +define+SIMULATION \
    -ntb_opts uvm-1.2 \
    +incdir+$PROC_DIR \
    +incdir+$SRC_DIR \
    +incdir+$UVM_HOME/src \
    $PROC_DIR/Main_Processor.v \
    $PROC_DIR/bpu.sv \
    $PROC_DIR/perf_counters.sv \
    $PROC_DIR/Adder.v \
    $PROC_DIR/black_box.v \
    $PROC_DIR/grey_box.v \
    $PROC_DIR/adder_internal.v \
    $PROC_DIR/ALU.v \
    $PROC_DIR/comp.v \
    $PROC_DIR/Control_Unit.v \
    $PROC_DIR/data_mem.v \
    $PROC_DIR/full_adder.v \
    $PROC_DIR/halfadder.v \
    $PROC_DIR/inst_mem.v \
    $PROC_DIR/mux2_1_1bit.v \
    $PROC_DIR/mux4_1_16bit.v \
    $PROC_DIR/reg_file.v \
    $PROC_DIR/wallace_8bit.v \
    $SRC_DIR/processor_interface.sv \
    $SRC_DIR/top.sv \
    -l compile.log \
    -debug_acc+all \
    -o simv

echo "=== Compile OK ==="

echo ""
echo "=== Running ==="

./simv \
    +UVM_TESTNAME=processor_test \
    +UVM_VERBOSITY=UVM_MEDIUM \
    +ntb_random_seed=14788478 \
    -l sim.log

echo ""
echo "=== Simulation done ==="
echo ""
grep -E "UVM_ERROR|UVM_FATAL|PASS|FAIL" sim.log | tail -30
