# SPDX-License-Identifier: GPL-3.0-or-later
set script_dir [file dirname [file normalize [info script]]]
set sample_dir [file normalize [file join $script_dir ..]]
set repo_root [file normalize [file join $sample_dir .. ..]]
set build_dir [file join $repo_root build retrofm_spectrum_xsim]

file mkdir $build_dir
create_project retrofm_spectrum_xsim $build_dir -part xc7z010clg400-1 -force
add_files -fileset sim_1 -norecurse [file join $sample_dir rtl retrofm_spectrum.sv]
add_files -fileset sim_1 -norecurse [file join $script_dir tb_retrofm_spectrum.sv]
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top tb_retrofm_spectrum [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
set sim_log [file join $build_dir retrofm_spectrum_xsim.sim sim_1 behav xsim simulate.log]
close_sim
set passed 0
if {[file exists $sim_log]} {
    set handle [open $sim_log r]
    set contents [read $handle]
    close $handle
    if {[string first "RETROFM SPECTRUM SELF-TEST PASS" $contents] >= 0} {
        set passed 1
    }
}
close_project
if {!$passed} {
    error "RetroFM spectrum self-test did not report PASS; inspect $sim_log"
}
puts "RetroFM spectrum self-test completed successfully"
