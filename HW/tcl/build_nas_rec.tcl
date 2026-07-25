set repo_root [file normalize [file dirname [info script]]/../..]

set proj_name "nas_rec_project"
set proj_dir "$repo_root/vivado"

file mkdir $proj_dir
cd $proj_dir

create_project -force $proj_name $proj_dir -part xc7a200tfbg484-1
set_property board_part opalkelly.com:xem7310-a200:part0:1.0 [current_project]

puts "Adding NAS and REC source files..."
add_files $repo_root/HW/src/NAS
add_files $repo_root/HW/src/REC

puts "Adding Clock Wizard IP..."
add_files $repo_root/HW/ip/clk_wiz_for_rec/clk_wiz_0.xci

puts "Adding REC constraints..."
add_files -fileset constrs_1 $repo_root/HW/const/rec_constraints.xdc

update_compile_order -fileset sources_1

puts "Project successfully created in: $proj_dir"

puts "Running synthesis + implementation + bitstream generation..."
launch_runs synth_1 -jobs 8
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "Build of $proj_name completed successfully"