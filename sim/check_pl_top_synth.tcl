# SPDX-License-Identifier: GPL-3.0-or-later
# Fast out-of-context elaboration/synthesis check for the integrated PL top.

set script_dir [file normalize [file dirname [info script]]]
set sample_dir [file normalize [file join $script_dir ".."]]
set rtl_dir [file join $sample_dir "rtl"]

source [file join $sample_dir "vivado" "vendor_sources.tcl"]
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

synth_design -top retrofm_pl_top -part xc7z010clg400-1 \
    -mode out_of_context -flatten_hierarchy rebuilt
create_clock -name clk_system -period 10.000 [get_ports s_axi_aclk]
create_clock -name clk_audio -period 12.500 [get_ports clk_audio]
set_clock_groups -asynchronous \
    -group [get_clocks clk_system] -group [get_clocks clk_audio]
report_utilization
puts "RETROFM_PL_TOP_SYNTH_OK"
