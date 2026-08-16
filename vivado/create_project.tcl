# SPDX-License-Identifier: GPL-3.0-or-later
# Reproducible full EBAZ4205 RetroFM implementation and bitstream build.

set script_dir [file normalize [file dirname [info script]]]
set sample_dir [file normalize [file join $script_dir ".."]]
set rtl_dir [file join $sample_dir "rtl"]
set output_dir [file join $sample_dir "build" "vivado" "retrofm_player"]
set report_dir [file join $output_dir "reports"]
file mkdir $output_dir
file mkdir $report_dir
# A failed rebuild must not leave an older bitstream/XSA looking current.
foreach stale_artifact [list \
        [file join $output_dir "retrofm_player.bit"] \
        [file join $output_dir "retrofm_player.xsa"]] {
    if {[file exists $stale_artifact]} {
        file delete -force $stale_artifact
    }
}

# These indicate broken or partially applied timing intent and must stop the
# build immediately rather than survive as Critical Warnings in vivado.log.
foreach constraint_message_id [list \
        {Constraints 18-515} \
        {Constraints 18-611} \
        {Constraints 18-612} \
        {Designutils 20-1307}] {
    set_msg_config -id $constraint_message_id -new_severity ERROR
}

create_project retrofm_player $output_dir -part xc7z010clg400-1 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

source [file join $script_dir "vendor_sources.tcl"]
retrofm_vendor::read_all $sample_dir

foreach source [list \
        retrofm_sync_fifo.sv \
        retrofm_fifo_prefetch_bridge.sv \
        retrofm_fractional_ce.sv \
        retrofm_event_scheduler.sv \
        retrofm_stereo_mixer.sv \
        retrofm_pcm_sample_hold.sv \
        retrofm_sigma_delta.sv \
        retrofm_spectrum.sv \
        retrofm_command_queue.sv \
        retrofm_buttons.sv \
        retrofm_sample_cdc.sv \
        retrofm_jt51_resampler.sv \
        retrofm_mute_controller.sv \
        retrofm_jt03_activity.sv \
        retrofm_opna_activity.sv \
        retrofm_opna_adpcmb_ram.sv \
        retrofm_pl_frontend.sv \
        retrofm_pl_top.sv] {
    read_verilog -sv [file join $rtl_dir $source]
}
read_verilog [file join $rtl_dir "retrofm_pl_bd.v"]

source [file join $script_dir "create_system_bd.tcl"]
set bd_file [get_files retrofm_system.bd]
# Compile the block design and its IP in the current Vivado process.  The
# Windows run-manager/VRS worker path can stall before writing an OOC netlist
# on this host; in-context synthesis is also the most direct way to time the
# complete PS/PL integration rather than a collection of cached checkpoints.
set_property synth_checkpoint_mode None $bd_file
generate_target all $bd_file
set wrapper_files [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper_files
read_xdc [file join $sample_dir "constr" "retrofm_player.xdc"]
set_property top retrofm_system_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

synth_design -top retrofm_system_wrapper -part xc7z010clg400-1 \
    -flatten_hierarchy rebuilt

# Apply and prove the explicit CDC physical contract after synthesis, when
# generated clocks and flattened endpoints are available.
source [file join $script_dir "cdc_constraints.tcl"]
retrofm_cdc::apply
source [file join $script_dir "io_constraints.tcl"]
retrofm_io::apply
write_checkpoint -force [file join $output_dir "retrofm_player_synth.dcp"]
opt_design
place_design
phys_opt_design -directive AggressiveExplore
# Explore alternate legal routing for the direct PS7 EMIO output pair as well
# as internal timing.  The post-route gate still enforces the exact 1 ns SPI
# pair-skew contract; this directive does not relax any constraint.
route_design -directive Explore

set route_path [file join $report_dir "route_status.rpt"]
set check_path [file join $report_dir "check_timing.rpt"]
set cdc_path [file join $report_dir "cdc.rpt"]
set exceptions_path [file join $report_dir "exceptions.rpt"]
set bus_skew_path [file join $report_dir "bus_skew.rpt"]
set spi_timing_path [file join $report_dir "spi_output_timing.rpt"]
report_route_status -file $route_path
report_utilization -file [file join $report_dir "utilization.rpt"]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 \
    -file [file join $report_dir "timing_summary.rpt"]
report_cdc -details -file $cdc_path
report_exceptions -summary -file $exceptions_path
report_bus_skew -file $bus_skew_path
check_timing -verbose -file $check_path
retrofm_io::check_routed $spi_timing_path
write_checkpoint -force [file join $output_dir "retrofm_player_routed.dcp"]

set check_handle [open $check_path r]
set check_text [read $check_handle]
close $check_handle
set route_handle [open $route_path r]
set route_text [read $route_handle]
close $route_handle
set cdc_handle [open $cdc_path r]
set cdc_text [read $cdc_handle]
close $cdc_handle
set exceptions_handle [open $exceptions_path r]
set exceptions_text [read $exceptions_handle]
close $exceptions_handle
set bus_skew_handle [open $bus_skew_path r]
set bus_skew_text [read $bus_skew_handle]
close $bus_skew_handle
if {[regexp {# of nets with routing errors[^:]*:[[:space:]]*([1-9][0-9]*)} \
        $route_text match route_error_count]} {
    error "Route status reports $route_error_count net(s) with routing errors"
}
foreach check_name [list no_clock constant_clock pulse_width_clock \
        unconstrained_internal_endpoints multiple_clock generated_clocks loops partial_input_delay \
        partial_output_delay latch_loops] {
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
    # 16 Gray-pointer bits + 49 command-payload bits + 80 physical sample
    # payload bits + 27 nonconstant YM-clock bits + 2 stable active-chip
    # selection bits = 174 setup endpoints.
    # The
    # legal PS7-to-primary-output SPI constraints add two constraints but
    # their combinational output paths are gated separately by check_routed.
    error "Expected ten max-delay DPO constraints/174 setup endpoints; inspect $exceptions_path"
}
set bus_skew_met_count [regexp -all {Slack \(MET\)} $bus_skew_text]
if {$bus_skew_met_count != 4 || [regexp {Slack \(VIOLATED\)} $bus_skew_text]} {
    error "Expected four Gray-pointer bus-skew constraints met; inspect $bus_skew_path"
}

# Audit the user PL ports explicitly.  DDR/FIXED_IO belong to the PS7 hard-IP
# interface and are constrained by its generated constraints, not this board
# overlay.
set expected_pl_ports [get_ports -quiet {BUTTON_N[*] AUDIO_SD_L AUDIO_SD_R \
    LCD_CS LCD_DC LCD_RES LCD_SCLK LCD_MOSI}]
if {[llength $expected_pl_ports] != 12} {
    error "Expected 12 constrained user PL ports, found $expected_pl_ports"
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
    error "Routed timing failed: setup slack=$setup_slack ns, hold slack=$hold_slack ns"
}

set routed_checkpoint [file join $output_dir "retrofm_player_routed.dcp"]
set bit_file [file join $output_dir "retrofm_player.bit"]
write_bitstream -force $bit_file
# This flow implements the design in the current process rather than through
# an implementation run.  Vivado 2024.2 can write the routed bitstream here,
# but write_hw_platform cannot recover that BIT through an implementation-run
# association.  build.ps1 therefore invokes package_routed.tcl in a fresh
# process after this script exits; that script reopens and rechecks this exact
# routed checkpoint before exporting the XSA.
puts "RETROFM_FULL_ROUTE_PASS setup_slack=$setup_slack hold_slack=$hold_slack routed_checkpoint=$routed_checkpoint bitstream=$bit_file next=package_routed.tcl"
