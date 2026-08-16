set sample_dir [file normalize [file join [file dirname [info script]] ".."]]
set build_dir [file join $sample_dir "build" "jt03_output_mix_xsim"]
file mkdir $build_dir
cd $build_dir
create_project retrofm_jt03_output_mix $build_dir -part xc7z010clg400-1 -force
read_verilog [file join $sample_dir "rtl" "vendor" "retrofm_jt03_output_mix.v"]
read_verilog -sv [file join $sample_dir "sim" "tb_retrofm_jt03_output_mix.sv"]
set_property top tb_retrofm_jt03_output_mix [get_filesets sim_1]
launch_simulation
run all
puts "RETROFM_JT03_OUTPUT_MIX_XSIM_PASS"
close_sim
