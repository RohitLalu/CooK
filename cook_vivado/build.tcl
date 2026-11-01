# build.tcl -- batch build of nexys4ddr_top from the checked-in project:
# synthesis, implementation, bitstream, reports, and a timing gate.
#
# From the repo root, in a Vivado Tcl shell (Windows: "Vivado <ver> Tcl Shell"):
#   vivado -mode batch -source cook_vivado/build.tcl -tclargs 0   ;# four cores, DDR2 unused
#   vivado -mode batch -source cook_vivado/build.tcl -tclargs 1   ;# gateway on tile 3 + DDR2
# Bring the board up with 0 first: it has no MIG, so a failure there is ours.
#
# Output in cook_vivado/out/:
#   cook_gw<G>.bit                     the bitstream (program.tcl loads it)
#   timing_gw<G>.rpt, util_gw<G>.rpt   timing summary and utilisation
#   drc_gw<G>.rpt
# Stops with an error when synthesis or implementation fails, or when setup
# (WNS) or hold (WHS) slack is negative: a bitstream that misses timing is
# not worth putting on the board.
#
# The GATEWAY generic is set on the fileset here, so it is saved in the
# project; the cook_gw block design must already exist for GATEWAY = 1
# (rtl/dma_ddr/create_cook_gw.tcl creates it, and does here if it is missing).

set gw  [expr {[llength $argv] > 0 ? [lindex $argv 0] : 1}]
if {$gw ne "0" && $gw ne "1"} { error "usage: -tclargs 0|1 (GATEWAY)" }
set here [file dirname [file normalize [info script]]]
set out  [file join $here out]
file mkdir $out

open_project [file join $here cook_vivado.xpr]

if {$gw == 1 && [llength [get_files -quiet cook_gw.bd]] == 0} {
    set gw_variant ddr
    source [file join $here .. rtl dma_ddr create_cook_gw.tcl]
}
set_property generic "GATEWAY=$gw" [get_filesets sources_1]
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
report_timing_summary -max_paths 20 -file [file join $out timing_gw$gw.rpt]
report_utilization                  -file [file join $out util_gw$gw.rpt]
report_drc                          -file [file join $out drc_gw$gw.rpt]

set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "COOK: GATEWAY=$gw  WNS=$wns ns  WHS=$whs ns"
if {$wns < 0 || $whs < 0} {
    error "timing not met (WNS $wns, WHS $whs): see [file join $out timing_gw$gw.rpt]"
}

set bit [file join [get_property DIRECTORY [get_runs impl_1]] nexys4ddr_top.bit]
file copy -force $bit [file join $out cook_gw$gw.bit]
puts "COOK: bitstream [file join $out cook_gw$gw.bit]"
close_project
