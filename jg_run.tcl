# ============================================================
#  jg_run.tcl    JasperGold 2024.09
# ============================================================

clear -all

analyze -sv09 \
    Processor/bpu.sv \
    Processor/bpu_properties.sv

elaborate -top bpu \
    -parameter NUM_ENTRIES 4 \
    -parameter PC_WIDTH 8

clock clk
reset rst

prove -all

prove -cover -all

report -summary
report -result

save -session jg_bpu_session
