set tcl_dir [file dirname [info script]]


set_property strategy Flow_AlternateRoutability [get_runs synth_1] 
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1] 
set_property strategy Performance_ExtraTimingOpt [get_runs impl_1] 
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1] 
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1] 
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1] 
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1] 

puts "Running synthesis..."
launch_runs synth_1 -jobs 10
wait_on_run synth_1

puts "Running implementation and bitstream generation..."
launch_runs impl_1 -to_step write_bitstream -jobs 10
wait_on_run impl_1

puts "NAS KWS synthesis, implementation, and bitstream generation completed successfully!"W