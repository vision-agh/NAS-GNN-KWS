set tcl_dir [file dirname [info script]]
source [file join $tcl_dir "build_kws_sys.tcl"]

puts "Running synthesis..."
launch_runs synth_1 -jobs 10
wait_on_run synth_1

puts "Running implementation and bitstream generation..."
launch_runs impl_1 -to_step write_bitstream -jobs 10
wait_on_run impl_1

puts "NAS KWS synthesis, implementation, and bitstream generation completed successfully!"