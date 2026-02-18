#*** External clock ***
set_property PACKAGE_PIN F23 [get_ports CLK_IN1_D_0_clk_p]
set_property IOSTANDARD LVDS [get_ports CLK_IN1_D_0_clk_p]

set_property PACKAGE_PIN E23 [get_ports CLK_IN1_D_0_clk_n]
set_property IOSTANDARD LVDS [get_ports CLK_IN1_D_0_clk_n]

#*** External reset button ***
set_property PACKAGE_PIN B4 [get_ports rst_ext_0]
set_property IOSTANDARD LVCMOS33 [get_ports rst_ext_0]

#*** I2S interface ***
set_property PACKAGE_PIN H6 [get_ports i2s_bclk_0]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_bclk_0]

set_property PACKAGE_PIN G6 [get_ports i2s_d_in_0]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_d_in_0]

set_property PACKAGE_PIN H8 [get_ports i2s_lr_0]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_lr_0]

