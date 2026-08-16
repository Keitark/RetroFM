set script_dir [file dirname [file normalize [info script]]]
set sample_dir [file dirname $script_dir]
set build_dir [file join $sample_dir build jt51_restart_xsim]
file mkdir $build_dir
create_project retrofm_jt51_restart_xsim $build_dir \
    -part xc7z010clg400-1 -force

source [file join $sample_dir vivado vendor_sources.tcl]
retrofm_vendor::assert_dependencies $sample_dir
set vendor_files [retrofm_vendor::source_files $sample_dir]
set wrapper_file [file join $sample_dir rtl vendor retrofm_jt51_wrapper.v]
set tb_file [file join $sample_dir sim tb_retrofm_jt51_restart.sv]

add_files -fileset sim_1 -norecurse $vendor_files
add_files -fileset sim_1 -norecurse $wrapper_file
add_files -fileset sim_1 -norecurse $tb_file
set_property file_type SystemVerilog [get_files -of_objects \
    [get_filesets sim_1] $wrapper_file]
set_property file_type SystemVerilog [get_files -of_objects \
    [get_filesets sim_1] $tb_file]
set_property top tb_retrofm_jt51_restart [get_filesets sim_1]
set_property verilog_define {SIMULATION} [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
set log_path [file join $build_dir retrofm_jt51_restart_xsim.sim \
    sim_1 behav xsim simulate.log]
close_sim
set handle [open $log_path r]
set log_text [read $handle]
close $handle
if {[string first "RETROFM JT51 RESTART SELF-TEST PASS" $log_text] < 0} {
    error "JT51 restart self-test did not pass"
}
close_project
puts "RETROFM_JT51_RESTART_XSIM_PASS"
