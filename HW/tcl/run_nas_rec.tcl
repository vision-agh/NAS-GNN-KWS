set tcl_dir [file dirname [info script]]

puts "Running synthesis..."
launch_runs synth_1 -jobs 10
wait_on_run synth_1

puts "Running implementation and bitstream generation..."
launch_runs impl_1 -to_step write_bitstream -jobs 10
wait_on_run impl_1

puts "NAS REC synthesis, implementation, and bitstream generation completed successfully!"