# SPDX-License-Identifier: GPL-3.0-or-later
set script_dir [file normalize [file dirname [info script]]]
set sample_dir [file normalize [file join $script_dir ".."]]
set project_dir [file join $sample_dir "build" "xsim_mute_controller"]
create_project retrofm_mute_controller_sim $project_dir \
    -part xc7z010clg400-1 -force
add_files -fileset sim_1 [list \
    [file join $sample_dir "rtl" "retrofm_mute_controller.sv"] \
    [file join $script_dir "tb_retrofm_mute_controller.sv"]]
set_property top tb_retrofm_mute_controller [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation
set sim_log [file join $project_dir \
    "retrofm_mute_controller_sim.sim" "sim_1" "behav" "xsim" \
    "simulate.log"]
close_sim
set passed 0
if {[file exists $sim_log]} {
    set handle [open $sim_log r]
    set contents [read $handle]
    close $handle
    set passed [expr {[string first \
        "PASS: RetroFM pending-unmute controller checks completed" \
        $contents] >= 0}]
}
close_project
if {!$passed} {
    error "Pending-unmute xsim did not report PASS; inspect $sim_log"
}
puts "RetroFM pending-unmute xsim completed successfully"
