<<<<<<< HEAD
<<<<<<< HEAD
# create_clock -period 5.000 -name clk -waveform {0.000 2.500} -add [get_ports -filter { NAME =~  "*clk*" && DIRECTION == "IN" }]
=======

>>>>>>> 68a19b5 (HW: sort source files, add NAS modules and GCNN-NAS integration logic, update xdc)
=======
# create_clock -period 5.000 -name clk -waveform {0.000 2.500} -add [get_ports -filter { NAME =~  "*clk*" && DIRECTION == "IN" }]
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
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


create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list u_clock_gen/inst/clk_out2]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 8 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {out_conf[0]} {out_conf[1]} {out_conf[2]} {out_conf[3]} {out_conf[4]} {out_conf[5]} {out_conf[6]} {out_conf[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 160 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {out_cls[0]} {out_cls[1]} {out_cls[2]} {out_cls[3]} {out_cls[4]} {out_cls[5]} {out_cls[6]} {out_cls[7]} {out_cls[8]} {out_cls[9]} {out_cls[10]} {out_cls[11]} {out_cls[12]} {out_cls[13]} {out_cls[14]} {out_cls[15]} {out_cls[16]} {out_cls[17]} {out_cls[18]} {out_cls[19]} {out_cls[20]} {out_cls[21]} {out_cls[22]} {out_cls[23]} {out_cls[24]} {out_cls[25]} {out_cls[26]} {out_cls[27]} {out_cls[28]} {out_cls[29]} {out_cls[30]} {out_cls[31]} {out_cls[32]} {out_cls[33]} {out_cls[34]} {out_cls[35]} {out_cls[36]} {out_cls[37]} {out_cls[38]} {out_cls[39]} {out_cls[40]} {out_cls[41]} {out_cls[42]} {out_cls[43]} {out_cls[44]} {out_cls[45]} {out_cls[46]} {out_cls[47]} {out_cls[48]} {out_cls[49]} {out_cls[50]} {out_cls[51]} {out_cls[52]} {out_cls[53]} {out_cls[54]} {out_cls[55]} {out_cls[56]} {out_cls[57]} {out_cls[58]} {out_cls[59]} {out_cls[60]} {out_cls[61]} {out_cls[62]} {out_cls[63]} {out_cls[64]} {out_cls[65]} {out_cls[66]} {out_cls[67]} {out_cls[68]} {out_cls[69]} {out_cls[70]} {out_cls[71]} {out_cls[72]} {out_cls[73]} {out_cls[74]} {out_cls[75]} {out_cls[76]} {out_cls[77]} {out_cls[78]} {out_cls[79]} {out_cls[80]} {out_cls[81]} {out_cls[82]} {out_cls[83]} {out_cls[84]} {out_cls[85]} {out_cls[86]} {out_cls[87]} {out_cls[88]} {out_cls[89]} {out_cls[90]} {out_cls[91]} {out_cls[92]} {out_cls[93]} {out_cls[94]} {out_cls[95]} {out_cls[96]} {out_cls[97]} {out_cls[98]} {out_cls[99]} {out_cls[100]} {out_cls[101]} {out_cls[102]} {out_cls[103]} {out_cls[104]} {out_cls[105]} {out_cls[106]} {out_cls[107]} {out_cls[108]} {out_cls[109]} {out_cls[110]} {out_cls[111]} {out_cls[112]} {out_cls[113]} {out_cls[114]} {out_cls[115]} {out_cls[116]} {out_cls[117]} {out_cls[118]} {out_cls[119]} {out_cls[120]} {out_cls[121]} {out_cls[122]} {out_cls[123]} {out_cls[124]} {out_cls[125]} {out_cls[126]} {out_cls[127]} {out_cls[128]} {out_cls[129]} {out_cls[130]} {out_cls[131]} {out_cls[132]} {out_cls[133]} {out_cls[134]} {out_cls[135]} {out_cls[136]} {out_cls[137]} {out_cls[138]} {out_cls[139]} {out_cls[140]} {out_cls[141]} {out_cls[142]} {out_cls[143]} {out_cls[144]} {out_cls[145]} {out_cls[146]} {out_cls[147]} {out_cls[148]} {out_cls[149]} {out_cls[150]} {out_cls[151]} {out_cls[152]} {out_cls[153]} {out_cls[154]} {out_cls[155]} {out_cls[156]} {out_cls[157]} {out_cls[158]} {out_cls[159]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 1 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list out_valid]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_200]
>>>>>>> 68a19b5 (HW: sort source files, add NAS modules and GCNN-NAS integration logic, update xdc)
=======
>>>>>>> 37dca1f (HW: modified project structure, added LIF module, changed naming)
