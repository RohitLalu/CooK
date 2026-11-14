# create_project.tcl -- creates the single-bus baseline's own Vivado project,
# single_bus/vivado_proj/sb_vivado/sb_vivado.xpr. Nothing of the NoC project
# (cook_vivado/) is opened or changed; the RTL the two share is added by
# reference from ../rtl and stays where it is.
#
# From the repo root, in a Vivado Tcl shell:
#   vivado -mode batch -source single_bus/vivado_proj/create_project.tcl
# Then build with build.tcl (same folder), or open the .xpr in the GUI.
#
# Synthesis top: sb_nexys4ddr_top. Constraints: the NoC board's
# rtl/board/nexys4ddr/nexys4ddr.xdc (same board, same port names).
# Simulation set sim_1: tb_sb_top (default; -generic_top TEST=0..3),
# tb_sb_bus, tb_sb_mem, tb_sb_board.

set here [file dirname [file normalize [info script]]]
set sb   [file normalize [file join $here ..]]
set repo [file normalize [file join $sb ..]]
set proj [file join $here sb_vivado]
if {[file exists $proj]} { error "$proj already exists: delete it to recreate the project" }

create_project sb_vivado $proj -part xc7a100tcsg324-1
set_property target_language Verilog [current_project]

add_files -norecurse [list \
    [file join $repo rtl include noc_defs.vh] \
    [file join $repo rtl include noc_funcs.vh] \
    [file join $repo rtl router link_buffer.v] \
    [file join $repo rtl network_interface address_decoder.v] \
    [file join $repo rtl network_interface ni.v] \
    [file join $repo rtl core picorv32.v] \
    [file join $repo rtl board reset_sync.v] \
    [file join $repo rtl board status_panel.v] \
    [file join $repo rtl board seven_seg.v] \
    [file join $sb rtl sb_bus.v] \
    [file join $sb rtl sb_mem_ni.v] \
    [file join $sb rtl sb_top.v] \
    [file join $sb rtl sb_nexys4ddr_top.v] \
    [file join $repo sw tile00.mem] \
    [file join $repo sw tile01.mem] \
    [file join $repo sw tile02.mem]]
foreach h {noc_defs.vh noc_funcs.vh} {
    set_property file_type {Verilog Header} [get_files $h]
}
set_property include_dirs [file join $repo rtl include] [get_filesets sources_1]
set_property top sb_nexys4ddr_top [get_filesets sources_1]

add_files -fileset constrs_1 -norecurse [file join $repo rtl board nexys4ddr nexys4ddr.xdc]

add_files -fileset sim_1 -norecurse [list \
    [file join $sb tb axi4_mem_model.v] \
    [file join $sb tb tb_sb_bus.v] \
    [file join $sb tb tb_sb_mem.v] \
    [file join $sb tb tb_sb_top.v] \
    [file join $sb tb tb_sb_board.v] \
    [file join $repo sw alltoall.mem] \
    [file join $sb sw ddr.mem]]
set_property include_dirs [file join $repo rtl include] [get_filesets sim_1]
set_property top tb_sb_top [get_filesets sim_1]

# the memory node's block design (SmartConnect + MIG)
set sb_variant ddr
source [file join $sb rtl create_sb_mem.tcl]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "SB: project created at [file join $proj sb_vivado.xpr]"
close_project
