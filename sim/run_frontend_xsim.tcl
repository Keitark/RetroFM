# SPDX-License-Identifier: GPL-3.0-or-later
# Vivado/xsim runner for the RetroFM AXI4-Lite register and FIFO front end.

set script_dir [file dirname [file normalize [info script]]]
set rtl_dir    [file normalize [file join $script_dir .. rtl]]
set repo_root  [file normalize [file join $script_dir .. .. ..]]
set build_dir  [file join $repo_root build retrofm_frontend_xsim]

file mkdir $build_dir
create_project retrofm_frontend_xsim $build_dir -part xc7z010clg400-1 -force

set rtl_files [list \
    [file join $rtl_dir retrofm_sync_fifo.sv] \
    [file join $rtl_dir retrofm_fifo_prefetch_bridge.sv] \
    [file join $rtl_dir retrofm_event_scheduler.sv] \
    [file join $rtl_dir retrofm_pl_frontend.sv]]
set tb_file [file join $script_dir tb_retrofm_pl_frontend.sv]

add_files -fileset sim_1 -norecurse $rtl_files
add_files -fileset sim_1 -norecurse $tb_file
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top tb_retrofm_pl_frontend [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
set sim_log [file join $build_dir retrofm_frontend_xsim.sim sim_1 behav xsim simulate.log]
close_sim

set simulation_passed 0
if {[file exists $sim_log]} {
    set log_handle [open $sim_log r]
    set log_text [read $log_handle]
    close $log_handle
    if {[string first "RETROFM FRONTEND SELF-TEST PASS" $log_text] >= 0} {
        set simulation_passed 1
    }
}
close_project

if {!$simulation_passed} {
    error "RetroFM front-end xsim test did not report PASS; inspect $sim_log"
}
puts "RetroFM front-end xsim self-test completed successfully"

