set repo_root [file normalize [file dirname [info script]]/../..]
set proj_name "kws_system"
set proj_dir "$repo_root/HW/vivado/kws"

set fp_ip_dir "$repo_root/HW/ip/fp/IP"
set fp_marker "$fp_ip_dir/FrontPanel-Subsystem-v1.1.0"
set fp_zip "$repo_root/HW/ip/fp/FrontPanel-Vivado-IP-Dist-v1.1.0.zip"
set fp_url "https://pins.opalkelly.com/downloads/1373/download?category_id=43"

if {![file exists $fp_marker]} {
    puts "FrontPanel IP not found — downloading v1.1.0..."
    file mkdir $fp_ip_dir
    exec curl -s -L -o $fp_zip $fp_url
    exec powershell -Command "Expand-Archive -Path '$fp_zip' -DestinationPath '$fp_ip_dir' -Force"
    file delete $fp_zip
    puts "FrontPanel IP installed."
}

file mkdir $proj_dir
cd $proj_dir

create_project -force $proj_name $proj_dir -part xc7a200tfbg484-1
set_property board_part opalkelly.com:xem7310-a200:part0:1.0 [current_project]

set_property ip_repo_paths $repo_root/HW/ip/fp/IP [current_project]
update_ip_catalog

add_files $repo_root/HW/src/NAS
add_files $repo_root/HW/src/GCNN
add_files $repo_root/HW/src/board_wrapper_files/ok_top_wrapper.sv

add_files $repo_root/HW/src/KWS.vhd
add_files $repo_root/HW/src/lif.sv
add_files $repo_root/HW/src/nas_pkg.sv
add_files $repo_root/HW/src/timestamp_gen.vhd
add_files $repo_root/HW/src/TOP.sv

add_files $repo_root/HW/ip/ok/clk_wiz_ok/clk_wiz_ok.xci
add_files $repo_root/HW/ip/ok/dist_mem_gen_0/dist_mem_gen_0.xci
add_files $repo_root/HW/ip/ok/dist_mem_gen_1/dist_mem_gen_1.xci
add_files $repo_root/HW/ip/ok/dist_mem_gen_2/dist_mem_gen_2.xci
add_files $repo_root/HW/ip/ok/dist_mem_gen_3/dist_mem_gen_3.xci
add_files $repo_root/HW/ip/ok/div_f/div_f.xci
add_files $repo_root/HW/ip/ok/div_t/div_t.xci
add_files $repo_root/HW/ip/ok/fifo_generator_0/fifo_generator_0.xci
add_files $repo_root/HW/ip/ok/fifo_generator_ok/fifo_generator_ok.xci
add_files $repo_root/HW/ip/ok/frontpanel_0/frontpanel_0.xci

add_files [glob $repo_root/HW/mem/*.mem]

set all_ips [get_ips]
if {$all_ips ne ""} {
    reset_target all $all_ips
    generate_target all $all_ips
}

add_files -fileset constrs_1 $repo_root/HW/const/ok_constr.xdc

set_property top ok_top_wrapper [current_fileset]
update_compile_order -fileset sources_1

add_files -fileset sim_1 $repo_root/HW/tb/kws_ut.sv
set_property top kws_ut [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "Project successfully created in: $proj_dir"