# create_sb_mem.tcl
# Builds the block design behind the single-bus baseline's memory node
# (sb_mem_ni): its AXI4 master -> SmartConnect -> memory. Source it with the
# single-bus Vivado project open (vivado_proj/create_project.tcl does):
#
#   set sb_variant ddr ; source <repo>/single_bus/rtl/create_sb_mem.tcl
#       -> sb_mem      SmartConnect (clock crossing) + MIG, Nexys4 DDR DDR2,
#                      128 MB. Same MIG configuration as the NoC's gateway
#                      (rtl/dma_ddr/mig_nexys4ddr.prj, shared, read-only).
#   set sb_variant sim ; source <repo>/single_bus/rtl/create_sb_mem.tcl
#       -> sb_mem_sim  SmartConnect + AXI BRAM controller + 64 KB block RAM,
#                      for simulating the AXI path without a DDR2 model
#
# Ports of both (the wrapper is <bd>_wrapper):
#   clk50, rst_n          system clock and active-low reset (bus domain)
#   mem_axi               AXI4 slave, 32-bit address and data, no ID:
#                         connects to sb_mem_ni's m_axi_*
# ddr variant only:
#   clk200                200 MHz MIG system/reference clock
#   ddr2_sdram            DDR2 pins
#   init_calib_complete   MIG calibration done
# The memory sits at address 0, which is what sb_mem_ni's DDR_BASE counts from.

if {![info exists sb_variant]} { set sb_variant ddr }
set sb_dir [file dirname [file normalize [info script]]]

if {$sb_variant eq "ddr"} {
    set bd_name sb_mem
} elseif {$sb_variant eq "sim"} {
    set bd_name sb_mem_sim
} else {
    error "sb_variant must be ddr or sim, got '$sb_variant'"
}
if {[llength [get_files -quiet $bd_name.bd]] > 0} {
    error "$bd_name.bd already exists in this project; remove it first"
}

create_bd_design $bd_name
current_bd_design $bd_name

# ---------------------------------------------------------------- ports
create_bd_port -dir I -type clk -freq_hz 50000000 clk50
create_bd_port -dir I -type rst rst_n
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports rst_n]

set axi [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 mem_axi]
set_property -dict [list \
    CONFIG.PROTOCOL AXI4 \
    CONFIG.ADDR_WIDTH 32 \
    CONFIG.DATA_WIDTH 32 \
    CONFIG.ID_WIDTH 0 \
    CONFIG.HAS_BURST 1 \
    CONFIG.HAS_LOCK 0 \
    CONFIG.HAS_CACHE 0 \
    CONFIG.HAS_PROT 0 \
    CONFIG.HAS_QOS 0 \
    CONFIG.HAS_REGION 0 \
    CONFIG.HAS_WSTRB 1 \
    CONFIG.HAS_BRESP 1 \
    CONFIG.HAS_RRESP 1 \
    CONFIG.MAX_BURST_LENGTH 1 \
    CONFIG.NUM_READ_OUTSTANDING 1 \
    CONFIG.NUM_WRITE_OUTSTANDING 1] $axi
set_property CONFIG.ASSOCIATED_BUSIF {mem_axi} [get_bd_ports clk50]
set_property CONFIG.ASSOCIATED_RESET {rst_n} [get_bd_ports clk50]

# ---------------------------------------------------------------- IP
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect sc
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] [get_bd_cells sc]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst50

connect_bd_intf_net [get_bd_intf_ports mem_axi] [get_bd_intf_pins sc/S00_AXI]
connect_bd_net [get_bd_ports clk50] [get_bd_pins sc/aclk] [get_bd_pins rst50/slowest_sync_clk]
connect_bd_net [get_bd_ports rst_n] [get_bd_pins rst50/ext_reset_in]
connect_bd_net [get_bd_pins rst50/peripheral_aresetn] [get_bd_pins sc/aresetn]

# ---------------------------------------------------------------- memory side
if {$sb_variant eq "ddr"} {
    create_bd_port -dir I -type clk -freq_hz 200000000 clk200
    create_bd_port -dir O init_calib_complete

    # SmartConnect crosses from clk50 to the MIG's ui_clk
    set_property CONFIG.NUM_CLKS 2 [get_bd_cells sc]

    create_bd_cell -type ip -vlnv xilinx.com:ip:mig_7series mig
    # as in create_cook_gw.tcl: a synced (OneDrive) project folder can be
    # briefly locked while the MIG renames a temporary folder, so retry
    set mig_cfg [list \
        CONFIG.BOARD_MIG_PARAM Custom \
        CONFIG.RESET_BOARD_INTERFACE Custom \
        CONFIG.MIG_DONT_TOUCH_PARAM Custom \
        CONFIG.XML_INPUT_FILE [file join $sb_dir .. .. rtl dma_ddr mig_nexys4ddr.prj]]
    for {set try 1} {1} {incr try} {
        if {![catch {set_property -dict $mig_cfg [get_bd_cells mig]} err]} { break }
        if {$try >= 5} { error "MIG configuration failed after $try tries: $err" }
        puts "create_sb_mem: MIG configuration attempt $try failed, retrying"
        after 3000
    }

    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rstui

    connect_bd_intf_net [get_bd_intf_pins sc/M00_AXI] [get_bd_intf_pins mig/S_AXI]
    make_bd_intf_pins_external -name ddr2_sdram [get_bd_intf_pins mig/DDR2]

    connect_bd_net [get_bd_ports clk200] [get_bd_pins mig/sys_clk_i]
    connect_bd_net [get_bd_ports rst_n]  [get_bd_pins mig/sys_rst] [get_bd_pins rstui/ext_reset_in]
    connect_bd_net [get_bd_pins mig/ui_clk] [get_bd_pins sc/aclk1] [get_bd_pins rstui/slowest_sync_clk]
    connect_bd_net [get_bd_pins mig/mmcm_locked] [get_bd_pins rstui/dcm_locked]
    connect_bd_net [get_bd_pins rstui/peripheral_aresetn] [get_bd_pins mig/aresetn]
    connect_bd_net [get_bd_pins mig/init_calib_complete] [get_bd_ports init_calib_complete]

    foreach p {app_sr_req app_ref_req app_zq_req} {
        if {[llength [get_bd_pins -quiet mig/$p]] > 0} {
            set c [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant tie_$p]
            set_property CONFIG.CONST_VAL 0 $c
            connect_bd_net [get_bd_pins $c/dout] [get_bd_pins mig/$p]
        }
    }
} else {
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl bram_ctrl
    set_property -dict [list \
        CONFIG.DATA_WIDTH 32 \
        CONFIG.SINGLE_PORT_BRAM 1 \
        CONFIG.ECC_TYPE 0] [get_bd_cells bram_ctrl]
    create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen bram
    set_property -dict [list CONFIG.Memory_Type Single_Port_RAM] [get_bd_cells bram]

    connect_bd_intf_net [get_bd_intf_pins sc/M00_AXI] [get_bd_intf_pins bram_ctrl/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins bram_ctrl/BRAM_PORTA] [get_bd_intf_pins bram/BRAM_PORTA]
    connect_bd_net [get_bd_ports clk50] [get_bd_pins bram_ctrl/s_axi_aclk]
    connect_bd_net [get_bd_pins rst50/peripheral_aresetn] [get_bd_pins bram_ctrl/s_axi_aresetn]
}

# ---------------------------------------------------------------- addresses
assign_bd_address
foreach seg [get_bd_addr_segs -quiet -of_objects [get_bd_addr_spaces mem_axi]] {
    set_property offset 0x00000000 $seg
    if {$sb_variant eq "sim"} { set_property range 64K $seg }
}

validate_bd_design
save_bd_design

set bd_file [get_files $bd_name.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper
if {$sb_variant eq "sim"} {
    foreach f [list $bd_file [get_files $wrapper]] {
        set_property used_in_synthesis false $f
        set_property used_in_implementation false $f
    }
}
puts "create_sb_mem: built $bd_name, wrapper $wrapper"
