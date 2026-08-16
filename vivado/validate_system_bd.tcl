# SPDX-License-Identifier: GPL-3.0-or-later
# Structural validation of the complete block design without synthesis.

set script_dir [file normalize [file dirname [info script]]]
set sample_dir [file normalize [file join $script_dir ".."]]
set rtl_dir [file join $sample_dir "rtl"]
set output_dir [file join $sample_dir "build" "vivado" "bd_validation"]
file mkdir $output_dir

create_project retrofm_system_validation $output_dir \
    -part xc7z010clg400-1 -force
source [file join $script_dir "vendor_sources.tcl"]
retrofm_vendor::read_all $sample_dir
foreach source [list \
        retrofm_sync_fifo.sv retrofm_fifo_prefetch_bridge.sv \
        retrofm_fractional_ce.sv retrofm_event_scheduler.sv \
        retrofm_stereo_mixer.sv retrofm_pcm_sample_hold.sv retrofm_sigma_delta.sv \
        retrofm_spectrum.sv retrofm_command_queue.sv retrofm_buttons.sv \
        retrofm_sample_cdc.sv retrofm_jt51_resampler.sv \
        retrofm_jt03_activity.sv retrofm_opna_activity.sv retrofm_opna_adpcmb_ram.sv \
        retrofm_pl_frontend.sv retrofm_pl_top.sv] {
    read_verilog -sv [file join $rtl_dir $source]
}
read_verilog [file join $rtl_dir "retrofm_pl_bd.v"]
source [file join $script_dir "create_system_bd.tcl"]
generate_target all [get_files retrofm_system.bd]
write_bd_tcl -force [file join $output_dir "retrofm_system.generated.tcl"]
puts "RETROFM_SYSTEM_BD_VALIDATION_OK"
