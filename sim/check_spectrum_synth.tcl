# SPDX-License-Identifier: GPL-3.0-or-later
set script_dir [file dirname [file normalize [info script]]]
set sample_dir [file normalize [file join $script_dir ..]]
set repo_root [file normalize [file join $sample_dir .. ..]]
set build_dir [file join $repo_root build retrofm_spectrum_ooc]
file mkdir $build_dir

create_project retrofm_spectrum_ooc $build_dir -part xc7z010clg400-1 -force
add_files -norecurse [file join $sample_dir rtl retrofm_spectrum.sv]
set_property file_type SystemVerilog [get_files *.sv]
synth_design -top retrofm_spectrum -part xc7z010clg400-1 -mode out_of_context
create_clock -name clk -period 10.000 [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks clk]
# Match the 100 MHz system-clock BUFG assumption used by the vendor OOC build.
# Without an OOC clock source, Vivado cannot estimate clock delay or skew.
set_property HD.CLK_SRC BUFGCTRL_X0Y1 [get_ports clk]
opt_design
place_design
phys_opt_design
route_design

set timing [report_timing_summary -return_string -delay_type min_max \
    -report_unconstrained -check_timing_verbose]
set util [report_utilization -return_string]
set route_status [report_route_status -return_string]
set timing_path [file join $build_dir timing_summary.rpt]
set util_path [file join $build_dir utilization.rpt]
set route_path [file join $build_dir route_status.rpt]
set check_path [file join $build_dir check_timing.rpt]
set handle [open $timing_path w]
puts $handle $timing
close $handle
set handle [open $util_path w]
puts $handle $util
close $handle
set handle [open $route_path w]
puts $handle $route_status
close $handle
check_timing -verbose -file $check_path
write_checkpoint -force [file join $build_dir retrofm_spectrum_routed.dcp]

if {[regexp {# of nets with routing errors[^:]*:[[:space:]]*([1-9][0-9]*)} \
        $route_status match route_error_count]} {
    error "RetroFM spectrum route has $route_error_count net(s) with errors"
}

set handle [open $check_path r]
set check_text [read $handle]
close $handle
# Missing input/output delays are expected for this OOC-only module.  All
# internal clocking and constraint categories remain hard failures.
foreach check_name [list no_clock constant_clock pulse_width_clock \
        unconstrained_internal_endpoints multiple_clock generated_clocks \
        loops partial_input_delay partial_output_delay latch_loops] {
    if {[regexp "checking ${check_name} \\((\[1-9\]\[0-9\]*)\\)" \
            $check_text match count]} {
        error "RetroFM spectrum check_timing reports $count $check_name issue(s)"
    }
}

set setup_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
if {[llength $setup_paths] == 0 || [llength $hold_paths] == 0} {
    error "RetroFM spectrum routed timing analysis returned no setup or hold path"
}
set setup_wns [get_property SLACK [lindex $setup_paths 0]]
set hold_whs [get_property SLACK [lindex $hold_paths 0]]
if {$setup_wns < 0.0 || $hold_whs < 0.0} {
    error "RetroFM spectrum routed timing failed: setup=$setup_wns hold=$hold_whs"
}
puts "RETROFM_SPECTRUM_ROUTED_OOC_PASS setup_WNS=$setup_wns hold_WHS=$hold_whs"
close_project
