# aclk {FREQ_HZ 50000000 CLK_DOMAIN cook_gw_clk50 PHASE 0.0} aclk1 {FREQ_HZ 81247969 CLK_DOMAIN cook_gw_mig_0_ui_clk PHASE 0}
# Clock Domain: cook_gw_clk50
create_clock -name aclk -period 20.000 [get_ports aclk]
# Clock Domain: cook_gw_mig_0_ui_clk
create_clock -name aclk1 -period 12.308 [get_ports aclk1]
# Generated clocks
