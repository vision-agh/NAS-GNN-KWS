set repo_root [file normalize [file dirname [info script]]/../..]
set proj_name "kws_system"
set proj_dir "$repo_root/HW/vivado/kws"

file mkdir $proj_dir
cd $proj_dir

create_project -force $proj_name $proj_dir -part xc7a200tfbg484-1
set_property board_part opalkelly.com:xem7310-a200:part0:1.0 [current_project]

add_files $repo_root/HW/src/NAS
add_files $repo_root/HW/src/GCNN
add_files $repo_root/HW/src/board_wrapper_files/ok_top_wrapper.sv

add_files $repo_root/HW/src/KWS.vhd
add_files $repo_root/HW/src/lif.sv
add_files $repo_root/HW/src/nas_pkg.sv
add_files $repo_root/HW/src/timestamp_gen.vhd
add_files $repo_root/HW/src/TOP.sv

add_files [glob $repo_root/HW/mem/*.mem]

import_files $repo_root/HW/ip/ok/clk_wiz_ok/clk_wiz_ok.xci
import_files $repo_root/HW/ip/ok/dist_mem_gen_0/dist_mem_gen_0.xci
import_files $repo_root/HW/ip/ok/dist_mem_gen_1/dist_mem_gen_1.xci
import_files $repo_root/HW/ip/ok/dist_mem_gen_2/dist_mem_gen_2.xci
import_files $repo_root/HW/ip/ok/dist_mem_gen_3/dist_mem_gen_3.xci
import_files $repo_root/HW/ip/ok/div_f/div_f.xci
import_files $repo_root/HW/ip/ok/div_t/div_t.xci
import_files $repo_root/HW/ip/ok/fifo_generator_ok/fifo_generator_ok.xci

# temporary
set_property -dict [list CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {50.000}] [get_ips clk_wiz_ok]

set_property -dict [list CONFIG.coefficient_file "$repo_root/HW/mem/lut_sigmoid_r.coe"] [get_ips dist_mem_gen_0]
set_property -dict [list CONFIG.coefficient_file "$repo_root/HW/mem/lut_sigmoid_z.coe"] [get_ips dist_mem_gen_1]
set_property -dict [list CONFIG.coefficient_file "$repo_root/HW/mem/lut_rescale_i_n.coe"] [get_ips dist_mem_gen_2]
set_property -dict [list CONFIG.coefficient_file "$repo_root/HW/mem/lut_tanh_n.coe"] [get_ips dist_mem_gen_3]

set all_ips [get_ips]
if {$all_ips ne ""} {
    reset_target all $all_ips
    generate_target all $all_ips
}

add_files -fileset constrs_1 $repo_root/HW/const/ok_constr.xdc

set_property top ok_top_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "Project successfully created in: $proj_dir"