############################################################################
# XEM7310 - Constraints file for NAS + OKAERTOOL
############################################################################

set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS True [current_design]

############################################################################
## FrontPanel Host Interface
############################################################################
set_property PACKAGE_PIN Y19 [get_ports {okHU[0]}]
set_property PACKAGE_PIN R18 [get_ports {okHU[1]}]
set_property PACKAGE_PIN R16 [get_ports {okHU[2]}]
set_property SLEW FAST [get_ports {okHU[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports {okHU[*]}]

set_property PACKAGE_PIN W19 [get_ports {okUH[0]}]
set_property PACKAGE_PIN V18 [get_ports {okUH[1]}]
set_property PACKAGE_PIN U17 [get_ports {okUH[2]}]
set_property PACKAGE_PIN W17 [get_ports {okUH[3]}]
set_property PACKAGE_PIN T19 [get_ports {okUH[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {okUH[*]}]

set_property PACKAGE_PIN AB22 [get_ports {okUHU[0]}]
set_property PACKAGE_PIN AB21 [get_ports {okUHU[1]}]
set_property PACKAGE_PIN Y22 [get_ports {okUHU[2]}]
set_property PACKAGE_PIN AA21 [get_ports {okUHU[3]}]
set_property PACKAGE_PIN AA20 [get_ports {okUHU[4]}]
set_property PACKAGE_PIN W22 [get_ports {okUHU[5]}]
set_property PACKAGE_PIN W21 [get_ports {okUHU[6]}]
set_property PACKAGE_PIN T20 [get_ports {okUHU[7]}]
set_property PACKAGE_PIN R19 [get_ports {okUHU[8]}]
set_property PACKAGE_PIN P19 [get_ports {okUHU[9]}]
set_property PACKAGE_PIN U21 [get_ports {okUHU[10]}]
set_property PACKAGE_PIN T21 [get_ports {okUHU[11]}]
set_property PACKAGE_PIN R21 [get_ports {okUHU[12]}]
set_property PACKAGE_PIN P21 [get_ports {okUHU[13]}]
set_property PACKAGE_PIN R22 [get_ports {okUHU[14]}]
set_property PACKAGE_PIN P22 [get_ports {okUHU[15]}]
set_property PACKAGE_PIN R14 [get_ports {okUHU[16]}]
set_property PACKAGE_PIN W20 [get_ports {okUHU[17]}]
set_property PACKAGE_PIN Y21 [get_ports {okUHU[18]}]
set_property PACKAGE_PIN P17 [get_ports {okUHU[19]}]
set_property PACKAGE_PIN U20 [get_ports {okUHU[20]}]
set_property PACKAGE_PIN N17 [get_ports {okUHU[21]}]
set_property PACKAGE_PIN N14 [get_ports {okUHU[22]}]
set_property PACKAGE_PIN V20 [get_ports {okUHU[23]}]
set_property PACKAGE_PIN P16 [get_ports {okUHU[24]}]
set_property PACKAGE_PIN T18 [get_ports {okUHU[25]}]
set_property PACKAGE_PIN V19 [get_ports {okUHU[26]}]
set_property PACKAGE_PIN AB20 [get_ports {okUHU[27]}]
set_property PACKAGE_PIN P15 [get_ports {okUHU[28]}]
set_property PACKAGE_PIN V22 [get_ports {okUHU[29]}]
set_property PACKAGE_PIN U18 [get_ports {okUHU[30]}]
set_property PACKAGE_PIN AB18 [get_ports {okUHU[31]}]
set_property SLEW FAST [get_ports {okUHU[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports {okUHU[*]}]

set_property PACKAGE_PIN N13 [get_ports okAA]
set_property IOSTANDARD LVCMOS18 [get_ports okAA]
############################################################################
## I2S ADC on board interface
############################################################################
set_property PACKAGE_PIN V4 [get_ports i2s_d_in]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_d_in]

set_property PACKAGE_PIN Y16 [get_ports i2s_bclk]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_bclk]

set_property PACKAGE_PIN AB15 [get_ports i2s_lr]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_lr]

############################################################################
## External AER OUT Interface
############################################################################
set_property PACKAGE_PIN Y12 [get_ports {out_data[0]}]
set_property PACKAGE_PIN G4 [get_ports {out_data[1]}]
set_property PACKAGE_PIN Y14 [get_ports {out_data[2]}]
set_property PACKAGE_PIN H4 [get_ports {out_data[3]}]
set_property PACKAGE_PIN W14 [get_ports {out_data[4]}]
set_property PACKAGE_PIN Y11 [get_ports {out_data[5]}]
set_property PACKAGE_PIN T15 [get_ports {out_data[6]}]
set_property PACKAGE_PIN V14 [get_ports {out_data[7]}]
set_property PACKAGE_PIN T14 [get_ports {out_data[8]}]
set_property PACKAGE_PIN V13 [get_ports {out_data[9]}]
set_property PACKAGE_PIN V15 [get_ports {out_data[10]}]
set_property PACKAGE_PIN U16 [get_ports {out_data[11]}]
set_property PACKAGE_PIN U15 [get_ports {out_data[12]}]
set_property PACKAGE_PIN T16 [get_ports {out_data[13]}]
set_property PACKAGE_PIN B2 [get_ports {out_data[14]}]
set_property PACKAGE_PIN J4 [get_ports {out_data[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {out_data[*]}]

set_property PACKAGE_PIN E1 [get_ports out_req_n]
set_property IOSTANDARD LVCMOS33 [get_ports out_req_n]
set_property PACKAGE_PIN D1 [get_ports out_ack_n]
set_property IOSTANDARD LVCMOS33 [get_ports out_ack_n]

############################################################################
## LEDs
############################################################################
set_property PACKAGE_PIN A13 [get_ports {leds[0]}]
set_property PACKAGE_PIN B13 [get_ports {leds[1]}]
set_property PACKAGE_PIN A14 [get_ports {leds[2]}]
set_property PACKAGE_PIN A15 [get_ports {leds[3]}]
set_property PACKAGE_PIN B15 [get_ports {leds[4]}]
set_property PACKAGE_PIN A16 [get_ports {leds[5]}]
set_property PACKAGE_PIN B16 [get_ports {leds[6]}]
set_property PACKAGE_PIN B17 [get_ports {leds[7]}]
set_property IOSTANDARD LVCMOS15 [get_ports {leds[*]}]