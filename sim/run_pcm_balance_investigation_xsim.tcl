# SPDX-License-Identifier: GPL-3.0-or-later
set script_dir [file dirname [file normalize [info script]]]
set sample_dir [file dirname $script_dir]
set build_dir [file join $sample_dir build pcm_balance_investigation_xsim]
create_project retrofm_pcm_balance_investigation $build_dir \
    -part xc7z010clg400-1 -force
read_verilog -sv [file join $sample_dir rtl retrofm_stereo_mixer.sv]
read_verilog -sv [file join $sample_dir rtl retrofm_pcm_sample_hold.sv]
read_verilog -sv [file join $script_dir tb_pcm_balance_investigation.sv]
set_property top tb_pcm_balance_investigation [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
set log_path [file join $build_dir retrofm_pcm_balance_investigation.sim \
    sim_1 behav xsim simulate.log]
close_sim
set handle [open $log_path r]
set log_text [read $handle]
close $handle
if {[string first "PCM BALANCE INVESTIGATION PASS" $log_text] < 0} {
    error "PCM balance investigation did not pass"
}
close_project
puts "RETROFM_PCM_BALANCE_INVESTIGATION_XSIM_PASS"
