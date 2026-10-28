# create_cook_gw.tcl
# Builds the AXI DMA block design that sits behind the gateway tile (gw_ni in
# mesh_top). Source it with a Vivado project open:
#
#   set gw_variant ddr ; source <repo>/rtl/dma_ddr/create_cook_gw.tcl
#       -> cook_gw      axi_dma + SmartConnect + MIG (Nexys4 DDR DDR2, 128 MB)
#   set gw_variant sim ; source <repo>/rtl/dma_ddr/create_cook_gw.tcl
#       -> cook_gw_sim  same axi_dma + SmartConnect, but a 64 KB block-RAM
#                       instead of the MIG, so the real axi_dma IP can be
#                       simulated without a DDR2 memory model
#
# Both variants expose the same gateway-facing ports, so they drop into the
# same RTL:
#   clk50, rst_n           system clock and active-low reset (NoC domain)
#   dma_ctrl               AXI4-Lite slave  -> axi_dma S_AXI_LITE (10-bit addr)
#   mm2s_axis              AXI-Stream master (DDR -> gateway)
#   s2mm_axis              AXI-Stream slave  (gateway -> DDR)
#   mm2s_introut, s2mm_introut
# ddr variant only:
#   clk200                 200 MHz MIG system/reference clock
#   ddr2_sdram             DDR2 pins
#   init_calib_complete    MIG calibration done
#
# Memory map seen by the DMA: 0x0000_0000 (DDR 128 MB, or BRAM 64 KB).
# Each variant also gets its HDL wrapper (<bd>_wrapper.v), added to the project
# but not set as top.

if {![info exists gw_variant]} { set gw_variant ddr }
set gw_dir [file dirname [file normalize [info script]]]

if {$gw_variant eq "ddr"} {
    set bd_name cook_gw
} elseif {$gw_variant eq "sim"} {
    set bd_name cook_gw_sim
} else {
    error "gw_variant must be ddr or sim, got '$gw_variant'"
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
create_bd_port -dir O -type intr mm2s_introut
create_bd_port -dir O -type intr s2mm_introut

# ---------------------------------------------------------------- IP
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma dma
set_property -dict [list \
    CONFIG.c_include_sg 0 \
    CONFIG.c_sg_include_stscntrl_strm 0 \
    CONFIG.c_include_mm2s 1 \
    CONFIG.c_include_s2mm 1 \
    CONFIG.c_m_axi_mm2s_data_width 32 \
    CONFIG.c_m_axis_mm2s_tdata_width 32 \
    CONFIG.c_m_axi_s2mm_data_width 32 \
    CONFIG.c_s_axis_s2mm_tdata_width 32 \
    CONFIG.c_mm2s_burst_size 16 \
    CONFIG.c_s2mm_burst_size 16 \
    CONFIG.c_sg_length_width 16 \
    CONFIG.c_addr_width 32] [get_bd_cells dma]

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect sc
set_property -dict [list CONFIG.NUM_SI 2 CONFIG.NUM_MI 1] [get_bd_cells sc]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst50

# ---------------------------------------------------------------- DMA side
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_MM2S] [get_bd_intf_pins sc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_S2MM] [get_bd_intf_pins sc/S01_AXI]

make_bd_intf_pins_external -name dma_ctrl  [get_bd_intf_pins dma/S_AXI_LITE]
make_bd_intf_pins_external -name mm2s_axis [get_bd_intf_pins dma/M_AXIS_MM2S]
make_bd_intf_pins_external -name s2mm_axis [get_bd_intf_pins dma/S_AXIS_S2MM]
set_property CONFIG.ASSOCIATED_BUSIF {dma_ctrl:mm2s_axis:s2mm_axis} [get_bd_ports clk50]
set_property CONFIG.ASSOCIATED_RESET {rst_n} [get_bd_ports clk50]

connect_bd_net [get_bd_ports clk50] \
    [get_bd_pins dma/s_axi_lite_aclk] \
    [get_bd_pins dma/m_axi_mm2s_aclk] \
    [get_bd_pins dma/m_axi_s2mm_aclk] \
    [get_bd_pins sc/aclk] \
    [get_bd_pins rst50/slowest_sync_clk]
connect_bd_net [get_bd_ports rst_n] [get_bd_pins rst50/ext_reset_in]
connect_bd_net [get_bd_pins rst50/peripheral_aresetn] \
    [get_bd_pins dma/axi_resetn] [get_bd_pins sc/aresetn]
connect_bd_net [get_bd_pins dma/mm2s_introut] [get_bd_ports mm2s_introut]
connect_bd_net [get_bd_pins dma/s2mm_introut] [get_bd_ports s2mm_introut]

# ---------------------------------------------------------------- memory side
if {$gw_variant eq "ddr"} {
    create_bd_port -dir I -type clk -freq_hz 200000000 clk200
    create_bd_port -dir O init_calib_complete

    # SmartConnect crosses from clk50 to the MIG's ui_clk
    set_property CONFIG.NUM_CLKS 2 [get_bd_cells sc]

    create_bd_cell -type ip -vlnv xilinx.com:ip:mig_7series mig
    # Configuring the MIG renames a temporary folder under <project>.gen. A
    # project inside a OneDrive (or other synced) folder can have that folder
    # briefly locked by the sync client ("error renaming ..."), so retry.
    set mig_cfg [list \
        CONFIG.BOARD_MIG_PARAM Custom \
        CONFIG.RESET_BOARD_INTERFACE Custom \
        CONFIG.MIG_DONT_TOUCH_PARAM Custom \
        CONFIG.XML_INPUT_FILE [file join $gw_dir mig_nexys4ddr.prj]]
    for {set try 1} {1} {incr try} {
        if {![catch {set_property -dict $mig_cfg [get_bd_cells mig]} err]} { break }
        if {$try >= 5} { error "MIG configuration failed after $try tries: $err" }
        puts "create_cook_gw: MIG configuration attempt $try failed, retrying"
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

    # self-refresh / refresh / ZQ requests are not used
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
# the gateway drives only the low 10 address bits; put the DMA registers at 0
foreach seg [get_bd_addr_segs -quiet -of_objects [get_bd_addr_spaces dma_ctrl]] {
    set_property offset 0x00000000 $seg
    set_property range 64K $seg
}
foreach sp {dma/Data_MM2S dma/Data_S2MM} {
    foreach seg [get_bd_addr_segs -quiet -of_objects [get_bd_addr_spaces $sp]] {
        set_property offset 0x00000000 $seg
    }
}

validate_bd_design
save_bd_design

set bd_file [get_files $bd_name.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper
if {$gw_variant eq "sim"} {
    # simulation only: keep it out of synthesis and implementation
    foreach f [list $bd_file [get_files $wrapper]] {
        set_property used_in_synthesis false $f
        set_property used_in_implementation false $f
    }
}
puts "create_cook_gw: built $bd_name, wrapper $wrapper"
