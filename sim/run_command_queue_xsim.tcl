# SPDX-License-Identifier: GPL-3.0-or-later
set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file normalize [file join $script_dir ".." "rtl"]]
set repo_root [file normalize [file join $script_dir ".." ".." ".."]]
set build_dir [file join $repo_root "build" "retrofm_command_queue_xsim"]
file mkdir $build_dir
create_project retrofm_command_queue_xsim $build_dir \
    -part xc7z010clg400-1 -force
add_files -fileset sim_1 -norecurse [list \
    [file join $rtl_dir "retrofm_sync_fifo.sv"] \
    [file join $rtl_dir "retrofm_fifo_prefetch_bridge.sv"] \
    [file join $rtl_dir "retrofm_command_queue.sv"] \
    [file join $script_dir "tb_retrofm_command_queue.sv"]]
set_property file_type SystemVerilog [get_files -of_objects \
    [get_filesets sim_1] "*.sv"]
set_property top tb_retrofm_command_queue [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
set sim_log [file join $build_dir "retrofm_command_queue_xsim.sim" \
    "sim_1" "behav" "xsim" "simulate.log"]
close_sim
set passed 0
if {[file exists $sim_log]} {
    set handle [open $sim_log r]
    set contents [read $handle]
    close $handle
    set passed [expr {[string first \
        "RETROFM COMMAND QUEUE SELF-TEST PASS" $contents] >= 0}]
}
close_project
if {!$passed} {
    error "Command queue xsim did not report PASS; inspect $sim_log"
}
puts "RetroFM command queue xsim completed successfully"
