## nexys4ddr.xdc -- constraints for nexys4ddr_top on the Digilent Nexys4 DDR
## (xc7a100tcsg324-1). Pin locations follow Digilent's Nexys-4-DDR-Master.xdc.

## 100 MHz oscillator. The MMCM's output clock is derived from this
## automatically; no separate create_clock is needed for it.
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK100MHZ }]

## Buttons: CPU_RESETN is the red reset button (active low), BTNC the centre
## button (clears router error flags).
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports { CPU_RESETN }]
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { BTNC }]

## LEDs
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { LED[0] }]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { LED[1] }]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { LED[2] }]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports { LED[3] }]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { LED[4] }]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports { LED[5] }]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports { LED[6] }]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports { LED[7] }]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports { LED[8] }]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports { LED[9] }]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { LED[10] }]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { LED[11] }]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { LED[12] }]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports { LED[13] }]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { LED[14] }]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports { LED[15] }]

## 7-segment display: SEG[0]=CA ... SEG[6]=CG, all active low
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { SEG[0] }]
set_property -dict { PACKAGE_PIN R10 IOSTANDARD LVCMOS33 } [get_ports { SEG[1] }]
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports { SEG[2] }]
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 } [get_ports { SEG[3] }]
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports { SEG[4] }]
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports { SEG[5] }]
set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports { SEG[6] }]
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports { DP }]

set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports { AN[0] }]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports { AN[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { AN[2] }]
set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 } [get_ports { AN[3] }]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports { AN[4] }]
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports { AN[5] }]
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 } [get_ports { AN[6] }]
set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports { AN[7] }]

## RGB LEDs (green half of LED16, blue half of LED17): DDR2 calibration done,
## AXI DMA interrupt pending
set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVCMOS33 } [get_ports { LED16_G }]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports { LED17_B }]

## DDR2 SDRAM (MT47H64M16HR-25E), banks 34/35 at 1.8 V. These repeat what the
## MIG IP applies from rtl/dma_ddr/mig_nexys4ddr.prj (same pins, same
## standards) so the pinout is visible here; the MIG also sets the DCI, VREF
## and timing constraints. Pinout from Digilent's Nexys4 DDR board files.
set_property -dict { PACKAGE_PIN M4 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[0] }]
set_property -dict { PACKAGE_PIN P4 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[1] }]
set_property -dict { PACKAGE_PIN M6 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[2] }]
set_property -dict { PACKAGE_PIN T1 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[3] }]
set_property -dict { PACKAGE_PIN L3 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[4] }]
set_property -dict { PACKAGE_PIN P5 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[5] }]
set_property -dict { PACKAGE_PIN M2 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[6] }]
set_property -dict { PACKAGE_PIN N1 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[7] }]
set_property -dict { PACKAGE_PIN L4 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[8] }]
set_property -dict { PACKAGE_PIN N5 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[9] }]
set_property -dict { PACKAGE_PIN R2 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[10] }]
set_property -dict { PACKAGE_PIN K5 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[11] }]
set_property -dict { PACKAGE_PIN N6 IOSTANDARD SSTL18_II } [get_ports { ddr2_addr[12] }]
set_property -dict { PACKAGE_PIN P2 IOSTANDARD SSTL18_II } [get_ports { ddr2_ba[0] }]
set_property -dict { PACKAGE_PIN P3 IOSTANDARD SSTL18_II } [get_ports { ddr2_ba[1] }]
set_property -dict { PACKAGE_PIN R1 IOSTANDARD SSTL18_II } [get_ports { ddr2_ba[2] }]
set_property -dict { PACKAGE_PIN L1 IOSTANDARD SSTL18_II } [get_ports { ddr2_cas_n }]
set_property -dict { PACKAGE_PIN N4 IOSTANDARD SSTL18_II } [get_ports { ddr2_ras_n }]
set_property -dict { PACKAGE_PIN N2 IOSTANDARD SSTL18_II } [get_ports { ddr2_we_n }]
set_property -dict { PACKAGE_PIN M1 IOSTANDARD SSTL18_II } [get_ports { ddr2_cke[0] }]
set_property -dict { PACKAGE_PIN K6 IOSTANDARD SSTL18_II } [get_ports { ddr2_cs_n[0] }]
set_property -dict { PACKAGE_PIN M3 IOSTANDARD SSTL18_II } [get_ports { ddr2_odt[0] }]
set_property -dict { PACKAGE_PIN L6 IOSTANDARD DIFF_SSTL18_II } [get_ports { ddr2_ck_p[0] }]
set_property -dict { PACKAGE_PIN L5 IOSTANDARD DIFF_SSTL18_II } [get_ports { ddr2_ck_n[0] }]
set_property -dict { PACKAGE_PIN T6 IOSTANDARD SSTL18_II } [get_ports { ddr2_dm[0] }]
set_property -dict { PACKAGE_PIN U1 IOSTANDARD SSTL18_II } [get_ports { ddr2_dm[1] }]
set_property -dict { PACKAGE_PIN R7 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[0] }]
set_property -dict { PACKAGE_PIN V6 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[1] }]
set_property -dict { PACKAGE_PIN R8 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[2] }]
set_property -dict { PACKAGE_PIN U7 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[3] }]
set_property -dict { PACKAGE_PIN V7 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[4] }]
set_property -dict { PACKAGE_PIN R6 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[5] }]
set_property -dict { PACKAGE_PIN U6 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[6] }]
set_property -dict { PACKAGE_PIN R5 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[7] }]
set_property -dict { PACKAGE_PIN T5 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[8] }]
set_property -dict { PACKAGE_PIN U3 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[9] }]
set_property -dict { PACKAGE_PIN V5 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[10] }]
set_property -dict { PACKAGE_PIN U4 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[11] }]
set_property -dict { PACKAGE_PIN V4 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[12] }]
set_property -dict { PACKAGE_PIN T4 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[13] }]
set_property -dict { PACKAGE_PIN V1 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[14] }]
set_property -dict { PACKAGE_PIN T3 IOSTANDARD SSTL18_II } [get_ports { ddr2_dq[15] }]
set_property -dict { PACKAGE_PIN U9 IOSTANDARD DIFF_SSTL18_II } [get_ports { ddr2_dqs_p[0] }]
set_property -dict { PACKAGE_PIN V9 IOSTANDARD DIFF_SSTL18_II } [get_ports { ddr2_dqs_n[0] }]
set_property -dict { PACKAGE_PIN U2 IOSTANDARD DIFF_SSTL18_II } [get_ports { ddr2_dqs_p[1] }]
set_property -dict { PACKAGE_PIN V2 IOSTANDARD DIFF_SSTL18_II } [get_ports { ddr2_dqs_n[1] }]

## Buttons are asynchronous and synchronised inside; LEDs and the display are
## slow human-facing outputs. None of them need I/O timing.
set_false_path -from [get_ports { CPU_RESETN BTNC }]
set_false_path -to   [get_ports { LED[*] SEG[*] DP AN[*] LED16_G LED17_B }]

## NoC clock (MMCM CLKOUT0, 50 MHz) and the MIG's ui_clk (81.25 MHz) only meet
## inside the SmartConnect's clock converter, which carries its own CDC
## constraints; the 200 MHz MIG input clock (CLKOUT1) is related to both
## through the same MMCM and needs nothing extra.

## Configuration bank voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
