set repo_root [file normalize [file dirname [info script]]/../..]
set proj_name "recording_system"
set proj_dir "$repo_root/HW/vivado/rec"

file mkdir $proj_dir
cd $proj_dir

create_project -force $proj_name $proj_dir -part xc7a200tfbg484-1
set_property board_part opalkelly.com:xem7310-a200:part0:1.0 [current_project]

add_files $repo_root/HW/src/NAS
add_files $repo_root/HW/src/REC

add_files $repo_root/HW/ip/ok/clk_wiz_for_rec/clk_wiz_0.xci

set all_ips [get_ips]
if {$all_ips ne ""} {
    upgrade_ip $all_ips
    reset_target all $all_ips
    generate_target all $all_ips
}

add_files -fileset constrs_1 $repo_root/HW/const/rec_constr.xdc

update_compile_order -fileset sources_1

puts "Project successfully created in: $proj_dir"