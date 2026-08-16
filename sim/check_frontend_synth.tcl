# SPDX-License-Identifier: GPL-3.0-or-later
# Out-of-context synthesizability check for the default-size PL front end.

set script_dir [file dirname [file normalize [info script]]]
set rtl_dir    [file normalize [file join $script_dir .. rtl]]
set repo_root  [file normalize [file join $script_dir .. .. ..]]
set report_dir [file join $repo_root build retrofm_frontend_synth]
file mkdir $report_dir

read_verilog -sv [file join $rtl_dir retrofm_sync_fifo.sv]
read_verilog -sv [file join $rtl_dir retrofm_fifo_prefetch_bridge.sv]
read_verilog -sv [file join $rtl_dir retrofm_event_scheduler.sv]
read_verilog -sv [file join $rtl_dir retrofm_pl_frontend.sv]

synth_design -top retrofm_pl_frontend -part xc7z010clg400-1 -mode out_of_context
create_clock -name s_axi_aclk -period 10.000 [get_ports s_axi_aclk]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir timing_100mhz.rpt]
write_checkpoint -force [file join $report_dir retrofm_pl_frontend_synth.dcp]

set primitive_cells [get_cells -hierarchical -filter {PRIMITIVE_LEVEL == LEAF}]
if {[llength $primitive_cells] == 0} {
    error "Front-end synthesis produced no primitive cells"
}
set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] == 0} {
    error "Front-end synthesis produced no timed register path"
}
set worst_slack [get_property SLACK [lindex $worst_path 0]]
if {$worst_slack < 0.0} {
    error "Front-end post-synthesis 100 MHz timing failed: WNS=$worst_slack ns"
}
puts "RetroFM front-end post-synthesis 100 MHz WNS: $worst_slack ns"
puts "RetroFM front-end out-of-context synthesis completed successfully"
