# SPDX-License-Identifier: GPL-3.0-or-later
# Non-project-mode compile check for the bounded Yamaha-core integration.

set script_dir [file normalize [file dirname [info script]]]
set sample_dir [file normalize [file join $script_dir ".."]]
set output_dir [file normalize [file join $sample_dir "build" "vendor_ooc"]]
file mkdir $output_dir

source [file join $script_dir "vendor_sources.tcl"]
retrofm_vendor::read_all $sample_dir

synth_design \
    -top retrofm_vendor_compile_top \
    -part xc7z010clg400-1 \
    -mode out_of_context \
    -flatten_hierarchy rebuilt

create_clock -name clk_system -period 10.000 [get_ports clk_system]
create_clock -name clk_audio -period 12.500 [get_ports clk_audio]
set_clock_uncertainty 0.200 [get_clocks {clk_system clk_audio}]
set_clock_groups -asynchronous \
    -group [get_clocks clk_system] \
    -group [get_clocks clk_audio]
set_property HD.CLK_SRC BUFGCTRL_X0Y1 [get_ports clk_system]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk_audio]

# Model a synchronous wrapper boundary so check_timing does not hide missing
# I/O constraints behind the fact that this is an out-of-context design.
set system_inputs [get_ports -quiet {rst_system clear_blocked \
    dac_test_sample[*] \
    jt51_cmd_valid jt51_cmd_reg[*] jt51_cmd_data[*] \
    jt03_cmd_valid jt03_cmd_reg[*] jt03_cmd_data[*]}]
set audio_inputs [get_ports -quiet {rst_audio ym2203_clock_hz[*]}]
set system_outputs [get_ports -quiet {jt51_cmd_ready jt03_cmd_ready \
    jt51_cmd_accept jt03_cmd_accept jt51_blocked_sticky \
    jt03_blocked_sticky}]
set audio_outputs [get_ports -quiet {jt51_cmd_done jt03_cmd_done \
    jt51_left[*] jt51_right[*] jt03_fm[*] jt03_psg[*] jt03_combined[*] \
    jt51_status[*] jt03_status[*] jt51_irq_n jt03_irq_n jt51_sample \
    jt03_sample pwm_left pwm_right}]

set_input_delay -clock clk_system -min 1.500 $system_inputs
set_input_delay -clock clk_system -max 2.000 $system_inputs
set_input_delay -clock clk_audio -min 1.500 $audio_inputs
set_input_delay -clock clk_audio -max 2.000 $audio_inputs
set_output_delay -clock clk_system -min 0.000 $system_outputs
set_output_delay -clock clk_system -max 2.000 $system_outputs
set_output_delay -clock clk_audio -min 0.000 $audio_outputs
set_output_delay -clock clk_audio -max 2.000 $audio_outputs

# OOC assumes each external reset is asserted asynchronously and released by
# the real system reset controller in its destination clock domain.  Upstream
# JT49 uses asynchronous clear internally, so constrain reset release as CDC
# reset behavior rather than as synchronous I/O data.
set_false_path -from [get_ports rst_system]
set_false_path -from [get_ports rst_audio]

report_utilization \
    -file [file join $output_dir "utilization_synth.rpt"]
report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 20 \
    -file [file join $output_dir "timing_synth.rpt"]
check_timing -verbose \
    -file [file join $output_dir "check_timing_synth.rpt"]
write_checkpoint -force [file join $output_dir "retrofm_vendor_synth.dcp"]

opt_design
place_design
phys_opt_design
route_design
phys_opt_design -hold_fix
route_design -preserve

set route_path [file join $output_dir "route_status.rpt"]
report_route_status -file $route_path
report_utilization \
    -file [file join $output_dir "utilization_routed.rpt"]
report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 20 \
    -file [file join $output_dir "timing_routed.rpt"]
report_cdc -details \
    -file [file join $output_dir "cdc_routed.rpt"]
set check_path [file join $output_dir "check_timing_routed.rpt"]
check_timing -verbose -file $check_path
write_checkpoint -force [file join $output_dir "retrofm_vendor_routed.dcp"]

set check_handle [open $check_path r]
set check_text [read $check_handle]
close $check_handle
set route_handle [open $route_path r]
set route_text [read $route_handle]
close $route_handle
if {[regexp {# of nets with routing errors[^:]*:[[:space:]]*([1-9][0-9]*)} \
        $route_text match route_error_count]} {
    error "Route status reports $route_error_count net(s) with routing errors"
}
foreach check_name [list no_clock constant_clock pulse_width_clock \
        unconstrained_internal_endpoints no_input_delay no_output_delay \
        multiple_clock generated_clocks loops partial_input_delay \
        partial_output_delay latch_loops] {
    if {[regexp "checking ${check_name} \\((\[1-9\]\[0-9\]*)\\)" \
            $check_text match count]} {
        error "check_timing reports $count $check_name issue(s)"
    }
}

set setup_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
if {[llength $setup_paths] == 0 || [llength $hold_paths] == 0} {
    error "Routed timing analysis returned no setup or hold path"
}
set setup_slack [get_property SLACK [lindex $setup_paths 0]]
set hold_slack [get_property SLACK [lindex $hold_paths 0]]
if {$setup_slack < 0.0 || $hold_slack < 0.0} {
    error "Routed timing failed: setup slack=$setup_slack ns, hold slack=$hold_slack ns"
}

puts "RETROFM_VENDOR_OOC_ROUTE_TIMING_PASS setup_slack=$setup_slack hold_slack=$hold_slack"
