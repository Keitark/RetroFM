# SPDX-License-Identifier: GPL-3.0-or-later
# Recheck an existing routed RetroFM checkpoint and export only after signoff.

set script_dir [file normalize [file dirname [info script]]]
set sample_dir [file normalize [file join $script_dir ".."]]
set output_dir [file join $sample_dir "build" "vivado" "retrofm_player"]
set report_dir [file join $output_dir "reports"]
set project_file [file join $output_dir "retrofm_player.xpr"]
set routed_dcp [file join $output_dir "retrofm_player_routed.dcp"]
foreach constraint_message_id [list \
        {Constraints 18-515} \
        {Constraints 18-611} \
        {Constraints 18-612} \
        {Designutils 20-1307}] {
    set_msg_config -id $constraint_message_id -new_severity ERROR
}
foreach required [list $project_file $routed_dcp] {
    if {![file exists $required]} {
        error "Missing routed-build input: $required"
    }
}

open_project $project_file
open_checkpoint $routed_dcp

# Re-resolve every CDC endpoint and launch-cell cardinality without adding a
# second copy of the constraints already serialized in the routed DCP.
source [file join $script_dir "cdc_constraints.tcl"]
foreach core {jt51 jt03} {
    set write_dest [retrofm_cdc::require_pins \
        "$core FIFO write Gray destination" \
        "*/command_bridge_i/u_${core}_fifo/write_gray_dst_meta_reg*/D" 4]
    set read_dest [retrofm_cdc::require_pins \
        "$core FIFO read Gray destination" \
        "*/command_bridge_i/u_${core}_fifo/read_gray_src_meta_reg*/D" 4]
    retrofm_cdc::launch_cells "$core FIFO write Gray source" $write_dest 4
    retrofm_cdc::launch_cells "$core FIFO read Gray source" $read_dest 4
}
retrofm_cdc::require_pins "FIFO command payload" \
    "*/jt*_i/held_*_reg*/D" 32
retrofm_cdc::require_pins "sample mailbox payload" \
    "*/jt*_sample_cdc_i/dst_data_reg*/D" 48
retrofm_cdc::require_pins "YM2203 reset-handshake config" \
    "*/ym2203_clock_audio_reg*/D" 27
retrofm_cdc::require_pins "system-to-audio scalar synchronizer" \
    "*/reset_request_audio_meta_reg/D" 1
retrofm_cdc::require_pins "audio reset acknowledgement" \
    "*/audio_reset_ack_meta_reg/D" 1
retrofm_cdc::require_pins "sample toggle synchronizers" \
    "*/jt*_sample_cdc_i/toggle_meta_reg/D" 2
source [file join $script_dir "io_constraints.tcl"]
retrofm_io::resolve

set prefix [file join $report_dir "package"]
set route_path "${prefix}_route_status.rpt"
set timing_path "${prefix}_timing_summary.rpt"
set cdc_path "${prefix}_cdc.rpt"
set exceptions_path "${prefix}_exceptions.rpt"
set bus_skew_path "${prefix}_bus_skew.rpt"
set spi_timing_path "${prefix}_spi_output_timing.rpt"
set check_path "${prefix}_check_timing.rpt"
set utilization_path "${prefix}_utilization.rpt"
report_route_status -file $route_path
report_utilization -file $utilization_path
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 -file $timing_path
report_cdc -details -file $cdc_path
report_exceptions -summary -file $exceptions_path
report_bus_skew -file $bus_skew_path
check_timing -verbose -file $check_path
retrofm_io::check_routed $spi_timing_path

proc retrofm_read_text {path} {
    set handle [open $path r]
    set value [read $handle]
    close $handle
    return $value
}
set route_text [retrofm_read_text $route_path]
set timing_text [retrofm_read_text $timing_path]
set cdc_text [retrofm_read_text $cdc_path]
set exceptions_text [retrofm_read_text $exceptions_path]
set bus_skew_text [retrofm_read_text $bus_skew_path]
set check_text [retrofm_read_text $check_path]

if {[regexp {# of nets with routing errors[^:]*:[[:space:]]*([1-9][0-9]*)} \
        $route_text match count]} {
    error "Route status reports $count net(s) with routing errors"
}
foreach check_name [list no_clock constant_clock pulse_width_clock \
        unconstrained_internal_endpoints multiple_clock generated_clocks loops \
        partial_input_delay partial_output_delay latch_loops] {
    if {[regexp "checking ${check_name} \\((\[1-9\]\[0-9\]*)\\)" \
            $check_text match count]} {
        error "check_timing reports $count $check_name issue(s)"
    }
}
if {[regexp {There are ([1-9][0-9]*) input ports with no input delay specified\.} \
        $check_text match count]} {
    error "check_timing reports $count genuinely unconstrained input(s)"
}
if {[regexp {There are ([1-9][0-9]*) ports with no output delay specified\.} \
        $check_text match count]} {
    error "check_timing reports $count genuinely unconstrained output(s)"
}
if {[regexp {CDC-[0-9]+[[:space:]]+Critical[[:space:]]+([1-9][0-9]*)} \
        $cdc_text match count]} {
    error "report_cdc contains a Critical CDC category with $count path(s)"
}
if {![regexp {False Path[[:space:]]+6[[:space:]]+16[[:space:]]+16} \
        $exceptions_text]} {
    error "Expected six false-path constraints/16 endpoints; inspect $exceptions_path"
}
if {![regexp {Max Delay DPO[[:space:]]+10[[:space:]]+174[[:space:]]+0} \
        $exceptions_text]} {
    error "Expected ten max-delay constraints/174 setup endpoints; inspect $exceptions_path"
}
set bus_skew_met_count [regexp -all {Slack \(MET\)} $bus_skew_text]
if {$bus_skew_met_count != 4 || [regexp {Slack \(VIOLATED\)} $bus_skew_text]} {
    error "Expected four Gray-pointer bus-skew constraints met; inspect $bus_skew_path"
}
if {![regexp {All user specified timing constraints are met} $timing_text]} {
    error "Timing summary does not declare all constraints met: $timing_path"
}

set expected_pl_ports [get_ports -quiet {BUTTON_N[*] AUDIO_SD_L AUDIO_SD_R \
    LCD_CS LCD_DC LCD_RES LCD_SCLK LCD_MOSI}]
if {[llength $expected_pl_ports] != 12} {
    error "Expected 12 user PL ports, found $expected_pl_ports"
}
foreach port $expected_pl_ports {
    if {[get_property PACKAGE_PIN $port] eq ""} {
        error "User PL port has no PACKAGE_PIN: $port"
    }
    if {[get_property IOSTANDARD $port] ne "LVCMOS33"} {
        error "User PL port is not LVCMOS33: $port"
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
    error "Routed timing failed: setup=$setup_slack ns hold=$hold_slack ns"
}

set bit_file [file join $output_dir "retrofm_player.bit"]
set xsa_file [file join $output_dir "retrofm_player.xsa"]
write_bitstream -force $bit_file
write_hw_platform -fixed -include_bit -force $xsa_file
puts "RETROFM_ROUTED_PACKAGE_PASS setup_slack=$setup_slack hold_slack=$hold_slack bitstream=$bit_file xsa=$xsa_file"
