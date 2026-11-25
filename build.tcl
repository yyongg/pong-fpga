# Build the bitstream:  vivado -mode batch -source build.tcl
# Output: build/pong_top.bit (+ timing/utilization reports)

set root [file dirname [file normalize [info script]]]
file mkdir $root/build

read_verilog -sv [glob $root/rtl/*.sv]
read_xdc $root/constraints/pynq_z2.xdc

synth_design -top pong_top -part xc7z020clg400-1
opt_design
place_design
route_design

report_timing_summary -file $root/build/timing.rpt
report_utilization    -file $root/build/utilization.rpt
write_bitstream -force $root/build/pong_top.bit
