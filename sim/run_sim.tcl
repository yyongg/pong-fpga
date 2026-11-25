# Run the testbenches with the Vivado simulator (xsim).
#
#   vivado -mode batch -source sim/run_sim.tcl                        all tests
#   vivado -mode batch -source sim/run_sim.tcl -tclargs tb_pong_game  one test
#
# Work files and logs go to build/sim/ (tb_pong_renderer also writes
# build/sim/frame.ppm, a picture of one rendered frame).

set root [file dirname [file dirname [file normalize [info script]]]]
set work $root/build/sim
file mkdir $work
cd $work
# Start clean: a stale xsim.dir (e.g. from an interrupted run) can hang xvlog
file delete -force xsim.dir .Xil {*}[glob -nocomplain xsim*.backup.* *.pb]

set all_tests {tb_video_sync tb_debounce tb_tmds_encoder tb_pong_game tb_pong_renderer tb_pong_top}
set tests [expr {[llength $argv] ? $argv : $all_tests}]

proc tool {name} {
  set exe [file join $::env(XILINX_VIVADO) bin $name]
  if {$::tcl_platform(platform) eq "windows"} { append exe .bat }
  return $exe
}

# Run a command, log its output; return 1 on success
proc step {log args} {
  if {[catch {exec {*}$args >& $log} msg]} {
    puts "  [file tail [lindex $args 0]] failed, see build/sim/$log"
    return 0
  }
  return 1
}

puts "Compiling..."
set srcs [concat [glob $root/rtl/*.sv] [glob $root/sim/tb_*.sv]]
if {![step compile.log [tool xvlog] -sv {*}$srcs] ||
    ![step compile_glbl.log [tool xvlog] $::env(XILINX_VIVADO)/data/verilog/src/glbl.v]} {
  exit 1
}

set failed {}
foreach tb $tests {
  puts -nonewline "[format %-18s $tb] "
  flush stdout
  if {$tb eq "tb_pong_top"} {
    set tops [list work.$tb work.glbl -L unisims_ver -L secureip]
  } else {
    set tops [list work.$tb]
  }
  if {![step $tb.elab.log [tool xelab] {*}$tops -s $tb -timescale 1ns/1ps]} {
    lappend failed $tb
    continue
  }
  step $tb.log [tool xsim] $tb -R
  set f [open $tb.log]; set out [read $f]; close $f
  if {[string match "*TEST PASSED*" $out]} {
    puts "PASS"
  } else {
    puts "FAIL  (build/sim/$tb.log)"
    lappend failed $tb
  }
}

if {[llength $failed]} {
  puts "\n[llength $failed] of [llength $tests] failed: $failed"
  exit 1
}
puts "\nAll [llength $tests] tests passed."
exit 0
