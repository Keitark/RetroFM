# SPDX-License-Identifier: GPL-3.0-or-later
set script_dir [file dirname [file normalize [info script]]]
set sample_dir [file dirname $script_dir]
set build_dir [file join $sample_dir build jt51_resampler_xsim]
create_project retrofm_jt51_resampler $build_dir \
    -part xc7z010clg400-1 -force
read_verilog -sv [file join $sample_dir rtl retrofm_jt51_resampler.sv]
read_verilog -sv [file join $script_dir tb_retrofm_jt51_resampler.sv]
set_property top tb_retrofm_jt51_resampler [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
set log_path [file join $build_dir retrofm_jt51_resampler.sim \
    sim_1 behav xsim simulate.log]
close_sim
set handle [open $log_path r]
set log_text [read $handle]
close $handle
if {[string first "RETROFM JT51 RESAMPLER SELF-TEST PASS" $log_text] < 0} {
    error "JT51 resampler self-test did not pass"
}
close_project
puts "RETROFM_JT51_RESAMPLER_XSIM_PASS"
