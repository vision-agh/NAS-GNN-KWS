<<<<<<< HEAD
<<<<<<< HEAD
# create_clock -period 5.000 -name clk -waveform {0.000 2.500} -add [get_ports -filter { NAME =~  "*clk*" && DIRECTION == "IN" }]
=======
>>>>>>> fb0443f (HW: fixing repository structure)
=======
>>>>>>> fb0443f1edbeeecd7de16c8196ab0c9a23a69f71
#*** External clock ***
set_property IOSTANDARD LVDS [get_ports clock_125p]

set_property PACKAGE_PIN F23 [get_ports clock_125p]
set_property PACKAGE_PIN E23 [get_ports clock_125n]
set_property IOSTANDARD LVDS [get_ports clock_125n]

#*** External reset button ***
set_property PACKAGE_PIN B4 [get_ports rst_ext]
set_property IOSTANDARD LVCMOS33 [get_ports rst_ext]

#*** I2S interface ***
set_property PACKAGE_PIN H6 [get_ports i2s_bclk]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_bclk]

set_property PACKAGE_PIN G6 [get_ports i2s_d_in]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_d_in]

set_property PACKAGE_PIN H8 [get_ports i2s_lr]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_lr]


#*** AER out bus & protocol handshake ***
#set_property PACKAGE_PIN M9 [get_ports {AER_DATA_OUT[0]}]
#set_property IOSTANDARD LVCMOS33 [get_ports {AER_DATA_OUT[0]}]

#set_property PACKAGE_PIN L8 [get_ports {AER_DATA_OUT[1]}]
#set_property IOSTANDARD LVCMOS33 [get_ports {AER_DATA_OUT[1]}]

#set_property PACKAGE_PIN M8 [get_ports {AER_DATA_OUT[2]}]
#set_property IOSTANDARD LVCMOS33 [get_ports {AER_DATA_OUT[2]}]

#set_property PACKAGE_PIN K8 [get_ports {AER_DATA_OUT[3]}]
#set_property IOSTANDARD LVCMOS33 [get_ports {AER_DATA_OUT[3]}]

#set_property PACKAGE_PIN M10 [get_ports {AER_DATA_OUT[4]}]
#set_property IOSTANDARD LVCMOS33 [get_ports {AER_DATA_OUT[4]}]

#set_property PACKAGE_PIN K9 [get_ports {AER_DATA_OUT[5]}]
#set_property IOSTANDARD LVCMOS33 [get_ports {AER_DATA_OUT[5]}]

#set_property PACKAGE_PIN G8 [get_ports {AER_DATA_OUT[6]}]
#set_property IOSTANDARD LVCMOS33 [get_ports {AER_DATA_OUT[6]}]


#set_property PACKAGE_PIN L10 [get_ports AER_REQ]
#set_property IOSTANDARD LVCMOS33 [get_ports AER_REQ]

#set_property PACKAGE_PIN J9 [get_ports AER_ACK]
#set_property IOSTANDARD LVCMOS33 [get_ports AER_ACK]

<<<<<<< HEAD
<<<<<<< HEAD

=======
>>>>>>> fb0443f (HW: fixing repository structure)
=======
>>>>>>> fb0443f1edbeeecd7de16c8196ab0c9a23a69f71
