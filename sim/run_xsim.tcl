# SPDX-License-Identifier: GPL-3.0-or-later
# Project-mode xsim runner for the bounded, vendor-neutral RetroFM RTL tests.
# Invoke with:
#   vivado.bat -mode batch \
#     -source samples/retrofm_player/sim/run_xsim.tcl

set script_dir [file dirname [file normalize [info script]]]
set rtl_dir    [file normalize [file join $script_dir .. rtl]]
set repo_root  [file normalize [file join $script_dir .. .. ..]]
set build_dir  [file join $repo_root build retrofm_xsim]

file mkdir $build_dir
create_project retrofm_xsim $build_dir -part xc7z010clg400-1 -force

set rtl_files [list \
    [file join $rtl_dir retrofm_sync_fifo.sv] \
    [file join $rtl_dir retrofm_fractional_ce.sv] \
    [file join $rtl_dir retrofm_stereo_mixer.sv] \
    [file join $rtl_dir retrofm_sigma_delta.sv] \
    [file join $rtl_dir retrofm_event_scheduler.sv]]
set tb_file [file join $script_dir tb_retrofm_rtl.sv]

add_files -fileset sim_1 -norecurse $rtl_files
add_files -fileset sim_1 -norecurse $tb_file
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top tb_retrofm_rtl [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
set sim_log [file join $build_dir retrofm_xsim.sim sim_1 behav xsim simulate.log]
close_sim
set simulation_passed 0
if {[file exists $sim_log]} {
    set log_handle [open $sim_log r]
    set log_text [read $log_handle]
    close $log_handle
    if {[string first "RETROFM RTL SELF-TEST PASS" $log_text] >= 0} {
        set simulation_passed 1
    }
}
close_project

if {!$simulation_passed} {
    error "RetroFM xsim self-test did not report PASS; inspect $sim_log"
}
puts "RetroFM xsim self-test completed successfully"
