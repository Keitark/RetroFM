# SPDX-License-Identifier: GPL-3.0-or-later
set script_dir [file dirname [file normalize [info script]]]
set sample_dir [file normalize [file join $script_dir ".."]]
set build_dir [file normalize [file join $sample_dir "build" "opna_adpcmb_ram_xsim"]]
file mkdir $build_dir
create_project retrofm_opna_adpcmb_ram_xsim $build_dir -part xc7z010clg400-1 -force
add_files -fileset sim_1 -norecurse [list \
    [file join $sample_dir rtl retrofm_opna_adpcmb_ram.sv] \
    [file join $script_dir tb_retrofm_opna_adpcmb_ram.sv]]
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top tb_retrofm_opna_adpcmb_ram [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
set sim_log [file join $build_dir "retrofm_opna_adpcmb_ram_xsim.sim" sim_1 behav xsim simulate.log]
close_sim
set handle [open $sim_log r]
set contents [read $handle]
close $handle
close_project
if {[string first "RETROFM OPNA ADPCM-B RAM SELF-TEST PASS" $contents] < 0} {
    error "OPNA ADPCM-B RAM xsim did not report PASS; inspect $sim_log"
}
puts "RetroFM OPNA ADPCM-B RAM xsim completed successfully"
