# Pipelined MIPS Processor — Branch Prediction Unit Design & UVM/Formal Verification

> **16-bit 4-stage pipelined MIPS processor** extended with a parameterized 2-bit saturating branch predictor, verified end-to-end using a UVM 1.2 constrained-random testbench and formally proven using Cadence JasperGold SVA.

---

## Results at a Glance

| Metric | Result |
|--------|--------|
| UVM errors (10,000 random instructions) | **0** |
| Instruction types passing | **All 16** |
| Branches verified (BPU consistency) | **662 / 662 (100%)** |
| Functional coverage bins hit | **100%** (all 4 BHT states, TP/TN/FP/FN, BTB hit/miss, flush) |
| JasperGold assertions proven | **12 / 12 (100%, unbounded)** |
| JasperGold cover points reached | **17 / 17 (100%)** |

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Processor Architecture](#2-processor-architecture)
3. [Instruction Set](#3-instruction-set)
4. [Branch Prediction Unit](#4-branch-prediction-unit)
5. [UVM Testbench](#5-uvm-testbench)
6. [Formal Verification](#6-formal-verification)
7. [Repository Structure](#7-repository-structure)
8. [Running the Simulation](#8-running-the-simulation)
9. [Running Formal Verification](#9-running-formal-verification)
10. [Key Engineering Challenges](#10-key-engineering-challenges)
11. [Tools & Dependencies](#11-tools--dependencies)

---

## 1. Project Overview

This project started as a **UVM verification environment for a pre-existing 4-stage pipelined MIPS processor**. The scope was then extended to include the full design, integration, verification, and formal proof of a **2-bit saturating Branch Prediction Unit (BPU)**.

The work covers three distinct engineering disciplines:

- **RTL Design** — designing the BPU from scratch in SystemVerilog and integrating it into the existing pipeline without breaking any pre-existing functionality
- **UVM Verification** — extending the constrained-random testbench with flush-aware FIFO alignment, BPU signal monitoring, a consistency checker, and functional coverage
- **Formal Verification** — writing and proving 5 SVA safety properties using JasperGold, with counterexample-guided property refinement

---

## 2. Processor Architecture

The DUT is a **16-bit 4-stage pipelined MIPS processor** with the following pipeline structure:

```
 ┌──────────────────────────────────────────────────────────┐
 │  Part 1 (IF)  │  Part 2 (ID)  │  Part 3 (EX)  │  Part 4 (WB)  │
 │  inst_mem     │  Control Unit  │  ALU           │  reg_file      │
 │  PC register  │  Reg File read │  data_mem      │  writeback     │
 │  BPU predict  │  BPU resolve   │                │                │
 └──────────────────────────────────────────────────────────┘
```

**Key signals monitored by the UVM testbench:**

| Signal | Description |
|--------|-------------|
| `inst_in` | Instruction driven into the pipeline |
| `inst_out_tb` | Instruction word at the WB stage |
| `wD_rf` | Writeback data to register file |
| `w_en[1:0]` | Register write enable (reconfig field) |
| `aD_rf[2:0]` | Destination register address |
| `mem_data_tb` | Data written to data memory (STORE) |
| `mem_en_tb` | Memory write enable |
| `mem_add_tb[2:0]` | Memory address |
| `actual_taken` | Jump resolved (pipelined to WB) |
| `pred_taken` | BPU prediction at fetch time (pipelined to WB) |
| `mispredicted` | Misprediction detected (pipelined to WB) |
| `flush` | Pipeline flush asserted (pipelined to WB) |
| `btb_hit` | BTB hit this cycle (pipelined to WB) |
| `bht_state[1:0]` | BHT counter value at fetch index (pipelined to WB) |

---

## 3. Instruction Set

The processor supports **16 instructions with 49 variants** across a 16-bit encoding:

```
 [15:12] opcode  [11] ctrl  [10:9] reconfig  [8:6] dest  [5:3] src1  [2:0] src2/mem
```

| Opcode | Instruction | Variants |
|--------|-------------|----------|
| `0000` | ADD | 16-bit, upper byte, lower byte |
| `0001` | SUB | 16-bit, upper byte, lower byte |
| `0010` | DEC | 16-bit, upper byte, lower byte |
| `0011` | INC | 16-bit, upper byte, lower byte |
| `0100` | AND / NAND | ctrl selects |
| `0101` | OR / NOR | ctrl selects |
| `0110` | XOR / XNOR | ctrl selects |
| `0111` | BUFF / INV | ctrl selects |
| `1000` | MUL | upper/lower byte |
| `1001` | MOV / MOVI | ctrl=0: reg-to-reg, ctrl=1: immediate |
| `1010` | LOAD | load from data memory |
| `1011` | STORE | store to data memory |
| `1100` | SHIFT | ctrl=0: left, ctrl=1: right |
| `1101` | JMP | unconditional jump with 3-bit displacement |
| `1110` | NOP | waste one cycle |
| `1111` | EOP | end of program |

The constrained-random driver generates instructions in the range `[16'h0000 : 16'hEFFF]`, covering all instruction types.

---

## 4. Branch Prediction Unit

### Design

The BPU implements a **2-level predictor** with a direct-mapped BTB and a 2-bit saturating BHT:

```
Fetch time:
  idx = fetch_pc[IDX_WIDTH-1:0]
  tag = fetch_pc[PC_WIDTH-1:IDX_WIDTH]
  
  btb_hit  = btb_valid[idx] && (btb_tag[idx] == tag)
  pred_taken = btb_hit && (bht[idx] >= 2'b10)
  
  if pred_taken: PC_next = btb_target[idx]  (speculative)
  else:          PC_next = PC + 1           (sequential)

Resolve time (decode stage):
  mispredicted = resolve_en && (
    (pred_taken_at_resolve != resolve_taken) ||
    (pred_taken_at_resolve && resolve_taken && target_mismatch)
  )
  
  if mispredicted: inject NOP (16'hEFFF) into IF/ID register → flush wrong path
  
  BHT update: saturating increment/decrement
  BTB update: only on taken jumps
```

### Parameters

| Parameter | Formal | UVM | Description |
|-----------|--------|-----|-------------|
| `NUM_ENTRIES` | 4 | 4 / 8 | BTB and BHT depth |
| `PC_WIDTH` | 8 | 8 | Program counter width |
| `IDX_WIDTH` | `$clog2(NUM_ENTRIES)` | auto | BTB index bits |
| `TAG_WIDTH` | `PC_WIDTH - IDX_WIDTH` | auto | BTB tag bits |

### BHT State Machine

```
      resolve_taken               resolve_taken
  ┌──────────────┐           ┌──────────────┐
  │              ▼           │              ▼
 [00]          [01]         [10]          [11]
Strongly     Weakly       Weakly       Strongly
Not-Taken    Not-Taken    Taken         Taken
  ▲              │           ▲              │
  └──────────────┘           └──────────────┘
    !resolve_taken              !resolve_taken

  predict NOT-TAKEN ◄──────────────────► predict TAKEN
  (bht < 2'b10)                          (bht >= 2'b10)

  Reset state: 2'b01 (Weakly Not-Taken)
```

### Pipeline Flush

When `mispredicted` fires, `flush_w` is asserted **combinatorially** in the same cycle — zeroing `inst_out` (the IF/ID register) to `16'hEFFF`. This achieves a **1-cycle flush penalty** compared to 2 cycles for a registered flush.

---

## 5. UVM Testbench

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    processor_test                        │
│  ┌──────────────────────────────────────────────────┐   │
│  │                 processor_env                    │   │
│  │  ┌─────────────────┐   ┌──────────────────────┐  │   │
│  │  │  processor_agent│   │  processor_scoreboard │  │   │
│  │  │  ┌───────────┐  │   │  - Instruction checks │  │   │
│  │  │  │  driver   │──┼───┤  - BPU consistency   │  │   │
│  │  │  │  sequencer│  │   │  - BPU_ACCURACY report│  │   │
│  │  │  └───────────┘  │   └──────────────────────┘  │   │
│  │  └────────┬────────┘           ▲                  │   │
│  │           │                    │                  │   │
│  │    ┌──────▼──────┐   ┌─────────┴──────────────┐  │   │
│  │    │   DUT       │   │   processor_monitor    │  │   │
│  │    │  (processor)│──►│   processor_subscriber │  │   │
│  │    └─────────────┘   │   (cover_branch CG)    │  │   │
│  │                      └────────────────────────┘  │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Scoreboard

The scoreboard performs **instruction-level checking** using a stateless reference model (initial register file values match the 16 MOVI init instructions driven at startup):

- **ALU instructions** — full data value check against `file[s1] op file[s2]`
- **MOVI** — full data value check against instruction encoding (`instrn[10] ? {data,8'h00} : {8'h00,data}`)
- **LOAD** — structural check: `reg_en` and `reg_add` correctness
- **MOVE** — structural check for reg-to-reg; full data check for MOVI variant
- **STORE** — address, enable, and data checks
- **BPU consistency** — `pred_taken == (btb_hit && bht_state >= 2'b10)` on every observed branch

### NOP Skip (FIFO Alignment)

The BPU flush injects `16'hEFFF` into the pipeline. The monitor captures this as a transaction but the driver never sent it. Without correction, the `drv_fifo` and `mon_fifo` become permanently misaligned after the first flush.

**Fix:** A `do-while` loop drains all `16'hEFFF` entries from `mon_fifo` before pairing with the current `exp_trans`:

```systemverilog
drv_fifo.get(exp_trans);
do begin
    mon_fifo.get(out_trans);
end while (out_trans.inst_out == 16'hEFFF && exp_trans.instrn != 16'hEFFF);
```

### Functional Coverage (`cover_branch`)

| Coverpoint | Bins |
|------------|------|
| `cp_bht_state` | `2'b00`, `2'b01`, `2'b10`, `2'b11` |
| `cp_pred_outcome` | True Positive, True Negative, False Positive, False Negative |
| `cp_btb` | BTB hit, BTB miss |
| `cp_flush` | Flush fired, Flush not fired |

All 17 cover points (including `cover_processor` from the original testbench) reached in the 10,000-instruction random test.

---

## 6. Formal Verification

Five SVA properties were written in `formal/bpu_properties.sv` and bound to `bpu.sv` using the SystemVerilog `bind` construct. The properties are in a separate module — no assertions are embedded in the RTL itself.

### Property Results

| # | Property | Result | Bound | What It Proves |
|---|----------|--------|-------|----------------|
| P1 | Misprediction correctness | **PROVEN** | Unbounded | `mispredicted` exactly matches the RTL formula at every resolve |
| P2 | No spurious misprediction | **PROVEN** | Unbounded | `mispredicted` stays low when `resolve_en` is not asserted |
| P3 (×4) | BHT overflow — all entries | **PROVEN** | Unbounded | Counter at `2'b11` never increments; proved via `genvar` for all 4 entries |
| P3 (×4) | BHT underflow — all entries | **PROVEN** | Unbounded | Counter at `2'b00` never decrements; proved via `genvar` for all 4 entries |
| P4 | `pred_taken` requires BTB hit | **PROVEN** | Unbounded | Cannot predict a target not stored in the BTB |
| P5 | BTB target consistency | **PROVEN** | Unbounded | After a taken update, BTB returns the correct target the following cycle |

**12 / 12 assertions proven. 17 / 17 cover points reached.**

### Counterexample-Guided Refinement

Three counterexamples were found and resolved — all were **property bugs**, not RTL bugs:

| CEX | Root Cause | Fix |
|-----|------------|-----|
| P1 | Compared fetch-time `pred_taken` against `resolve_taken` — BHT may update between fetch and resolve, making them different computations | Rewrote P1 to check `mispredicted` equals the RTL's exact combinational formula using resolve-time state |
| P2 | Same timing issue in the opposite direction | Simplified to: `!resolve_en |-> !mispredicted` |
| P5 | Used `\|->` (same-cycle) to check BTB after a non-blocking update — NBA commits after the posedge, not at it | Changed to `\|=>` (next-cycle implication) |

---

## 7. Repository Structure

```
.
├── Processor/                  # RTL design files
│   ├── Main_Processor.v        # Top-level pipeline (modified: BPU integrated)
│   ├── bpu.sv                  # Branch Prediction Unit (NEW)
│   ├── perf_counters.sv        # Hardware performance counters (NEW)
│   ├── tb_bpu.sv               # BPU isolation testbench (NEW)
│   ├── ALU.v                   # Arithmetic Logic Unit
│   ├── Control_Unit.v          # Instruction decoder & control signals
│   ├── reg_file.v              # 8×16 register file
│   ├── data_mem.v              # Data memory
│   ├── inst_mem.v              # Instruction memory
│   ├── adder_internal.v        # PC adder
│   ├── mux2_1_1bit.v           # 2:1 mux primitive
│   └── ...                     # Other submodules
│
├── src/                        # UVM testbench
│   ├── top.sv                  # DUT + interface instantiation (modified)
│   ├── processor_interface.sv  # Clocking blocks + BPU signals (modified)
│   ├── processor_sequence.sv   # Transaction + sequences (modified)
│   ├── processor_monitor.sv    # Pipeline output capture (modified)
│   ├── processor_scoreboard.sv # Checker + BPU consistency (modified)
│   ├── processor_subscriber.sv # cover_branch covergroup (modified)
│   ├── processor_driver.sv     # Constrained-random stimulus
│   ├── processor_test.sv       # UVM test class
│   ├── processor_env.sv        # UVM environment
│   ├── process_agent.sv        # UVM agent
│   ├── processor_testbench_pkg.sv  # Package include file
│   └── Makefile.vcs            # VCS compile & run script
│
├── formal/                     # Formal verification
│   ├── bpu_properties.sv       # 5 SVA properties + bind (NEW)
│   └── jg_run.tcl              # JasperGold batch script (NEW)
│
├── Instructions/               # Stimulus files
│   ├── instructions.txt        # Random instruction stream
│   └── instructions_init_reg.txt  # Register initialization sequence
│
└── README.md
```

---

## 8. Running the Simulation

### Prerequisites

- Synopsys VCS (tested with VCS 2024)
- UVM 1.2 (bundled with VCS at `$VCS_HOME/etc/uvm-1.2`)

### EDA Playground (Quick Start)

1. Upload all files from `Processor/` and `src/` to the respective tabs
2. Select **Synopsys VCS** as the simulator
3. Set UVM version to **UVM 1.2**
4. Hit **Run**

### Local VCS

```bash
cd src/

# Compile
vcs -sverilog -ntb_opts uvm-1.2 \
    -f filelist.f \
    -o simv \
    +incdir+$VCS_HOME/etc/uvm-1.2/src \
    $VCS_HOME/etc/uvm-1.2/src/uvm_pkg.sv

# Run
./simv +UVM_TESTNAME=processor_test +UVM_VERBOSITY=UVM_LOW
```

### Expected Output

```
--- UVM Report Summary ---
UVM_ERROR :    0
UVM_FATAL :    0

[BHT_PRED_PASS]   662
[BPU_ACCURACY]      1   ← "Branch prediction: 662 total, 662 correct, accuracy=100.0%"
[INSTRUCTION_WORD_PASS] 10000
[LOAD_PASS ]   701
[MOVE_PASS ]   625
[STORE_PASS]   671
[JUMP/EOP_PASS]  1315
... (all other instruction types PASS)
```

---

## 9. Running Formal Verification

### Prerequisites

- Cadence JasperGold 2024.09 (or compatible version)

### Run

```bash
# From project root
jg -batch -tcl formal/jg_run.tcl
```

Or interactively:

```bash
jg formal/jg_run.tcl
```

### Expected Output

```
SUMMARY
  assertions : 12
   - proven  : 12  (100%)
   - cex     :  0
  covers     : 17
   - covered : 17  (100%)
```

---

## 10. Key Engineering Challenges

### 1. Simulation Scheduling Race (Active Region vs. NBA)

**Problem:** BPU isolation testbench — 18 of 20 checks failed. Tests driving resolve inputs then reading outputs at `@(posedge clk)` were reading stale pre-update values.

**Root cause:** `@(posedge clk)` resumes the testbench in the *active region*. Non-blocking assignments (`<=`) commit in the *NBA region*, which follows. The testbench was reading FF outputs before they updated.

**Fix:** Drive inputs at `@(negedge clk)`, sample outputs 1 ns after posedge. This is the fundamental reason UVM clocking blocks with input/output skews exist.

### 2. Instruction Word Used as PC Address

**Problem:** BTB assertion fired — target inconsistent after update.

**Root cause:** `pc_2[7:0]` is the lower byte of the 16-bit instruction *word* pipeline register, not the 8-bit program counter. Both have the same bit width — a naming collision.

**Fix:** Added `pc_addr_d1` — a 1-cycle delayed register of `pc_out` (the actual PC counter) — as the resolve PC input to the BPU.

### 3. Gated Clock Domain Crossing

**Problem:** BTB assertion fired at 1,990,615,000 ps with `idx=x`. Only appeared after many EOP events.

**Root cause:** `pc_out` is registered on `clk_mod` (= `clk & ~eop`), a gated clock. `pc_addr_d1` was registered on plain `clk`. Every EOP cycle, `clk_mod` paused while `clk` kept running, causing `pc_addr_d1` to drift and eventually capture an X-state.

**Fix:** Changed `pc_addr_d1` to `posedge clk_mod`. Rule: any register sampling from a gated-clock domain must itself be in that domain.

### 4. BPU Signal Pipeline Alignment

**Problem:** `BPU_ACCURACY: No branches observed in this test` — scoreboard never saw `actual_taken = 1`.

**Root cause:** `actual_taken = jmp_cu` fires combinatorially in the *decode* stage. The monitor triggers when `inst_out_tb` changes in the *WB* stage — 3 pipeline stages later. By then, `jmp_cu` had been deasserted for 3 cycles.

**Fix:** Pipelined all 6 BPU observation signals through 3 `always@(posedge clk)` stages to align them with `inst_out_tb` at the WB stage.

### 5. FIFO Misalignment from BPU-Injected NOPs

**Problem:** Adding any stateful verification to the scoreboard caused 6,000+ cascade errors.

**Root cause:** The BPU flush injects `16'hEFFF` into the pipeline. The monitor captures this NOP as a real transaction but the driver never sent it. After the first flush, every `(exp_trans, out_trans)` pair is permanently offset by 1.

**Fix:** A `do-while` loop in the scoreboard drains all `16'hEFFF` entries from `mon_fifo` before pairing with `exp_trans`, using the exact injected value as the filter key.

---

## 11. Tools & Dependencies

| Tool | Version | Purpose |
|------|---------|---------|
| Synopsys VCS | 2024 | RTL simulation, UVM |
| Cadence JasperGold | 2024.09 | Formal property verification |
| SystemVerilog | IEEE 1800-2012 | RTL + testbench language |
| UVM | 1.2 | Verification methodology |
| EDA Playground | — | Cloud simulation (alternative) |

---

## Author

**Venkata Sri Sudha Renduchintala**
MS Electrical & Computer Engineering — University of Florida
Cadence UVM Certified

---

*Processor RTL originally developed as a course project. UVM testbench, BPU design, BPU integration, scoreboard fixes, and formal verification layer developed as a personal extension project.*
