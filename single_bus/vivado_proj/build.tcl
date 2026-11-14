# build.tcl -- batch build of the single-bus baseline (sb_nexys4ddr_top):
# synthesis, implementation, bitstream, reports, and a timing gate. The
# counterpart of cook_vivado/build.tcl, on its own project.
#
# From the repo root, in a Vivado Tcl shell (create_project.tcl first, once):
#   vivado -mode batch -source single_bus/vivado_proj/build.tcl -tclargs 0   ;# no DDR2
#   vivado -mode batch -source single_bus/vivado_proj/build.tcl -tclargs 1   ;# with DDR2 (MIG)
# Output in single_bus/vivado_proj/out/: sb_ddr<D>.bit, timing_ddr<D>.rpt,
# util_ddr<D>.rpt, drc_ddr<D>.rpt. Program it with the NoC's
# cook_vivado/program.tcl (it takes any .bit).
# Stops with an error when a run fails or when setup or hold slack is negative.

set ddr [expr {[llength $argv] > 0 ? [lindex $argv 0] : 1}]
if {$ddr ne "0" && $ddr ne "1"} { error "usage: -tclargs 0|1 (DDR)" }
set here [file dirname [file normalize [info script]]]
set out  [file join $here out]
file mkdir $out

open_project [file join $here sb_vivado sb_vivado.xpr]
set_property generic "DDR=$ddr" [get_filesets sources_1]
update_compile_order -fileset sources_1

set jobs 4
reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "synthesis failed: see [get_property DIRECTORY [get_runs synth_1]]/runme.log"
}
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "implementation failed: see [get_property DIRECTORY [get_runs impl_1]]/runme.log"
}

open_run impl_1
report_timing_summary -max_paths 20 -file [file join $out timing_ddr$ddr.rpt]
report_utilization                  -file [file join $out util_ddr$ddr.rpt]
report_drc                          -file [file join $out drc_ddr$ddr.rpt]

set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "SB: DDR=$ddr  WNS=$wns ns  WHS=$whs ns"
if {$wns < 0 || $whs < 0} {
    error "timing not met (WNS $wns, WHS $whs): see [file join $out timing_ddr$ddr.rpt]"
}

set bit [file join [get_property DIRECTORY [get_runs impl_1]] sb_nexys4ddr_top.bit]
file copy -force $bit [file join $out sb_ddr$ddr.bit]
puts "SB: bitstream [file join $out sb_ddr$ddr.bit]"
close_project
