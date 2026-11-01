# program.tcl -- load a bitstream into the Nexys4 DDR over its USB-JTAG port
# (the board's PROG/UART micro-USB, power switch on). Volatile: the design is
# gone after a power cycle, which is what a test session wants.
#
#   vivado -mode batch -source cook_vivado/program.tcl -tclargs cook_vivado/out/cook_gw0.bit

if {[llength $argv] != 1} { error "usage: -tclargs <file.bit>" }
set bit [file normalize [lindex $argv 0]]
if {![file exists $bit]} { error "no such bitstream: $bit" }

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev eq ""} { error "no xc7a100t on the JTAG chain: board connected and powered?" }
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "COOK: programmed $dev with $bit"
close_hw_target
disconnect_hw_server
close_hw_manager
