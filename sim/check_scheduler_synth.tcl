# SPDX-License-Identifier: GPL-3.0-or-later
set script_dir [file dirname [file normalize [info script]]]
set sample_dir [file normalize [file join $script_dir ..]]
set repo_root [file normalize [file join $sample_dir .. ..]]
set build_dir [file join $repo_root build retrofm_scheduler_ooc]
file mkdir $build_dir

create_project retrofm_scheduler_ooc $build_dir \
    -part xc7z010clg400-1 -force
add_files -norecurse [file join $sample_dir rtl retrofm_event_scheduler.sv]
set_property file_type SystemVerilog [get_files *.sv]
synth_design -top retrofm_event_scheduler -part xc7z010clg400-1 \
    -mode out_of_context
create_clock -name clk -period 10.000 [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y1 [get_ports clk]
opt_design
place_design
phys_opt_design
route_design

set setup_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
if {[llength $setup_paths] == 0 || [llength $hold_paths] == 0} {
    error "RetroFM scheduler routed timing returned no setup or hold path"
}
set setup_wns [get_property SLACK [lindex $setup_paths 0]]
set hold_whs [get_property SLACK [lindex $hold_paths 0]]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
report_utilization -file [file join $build_dir utilization.rpt]
report_route_status -file [file join $build_dir route_status.rpt]
write_checkpoint -force [file join $build_dir retrofm_scheduler_routed.dcp]
if {$setup_wns < 0.0 || $hold_whs < 0.0} {
    error "RetroFM scheduler routed timing failed: setup=$setup_wns hold=$hold_whs"
}
puts "RETROFM_SCHEDULER_ROUTED_OOC_PASS setup_WNS=$setup_wns hold_WHS=$hold_whs"
close_project
