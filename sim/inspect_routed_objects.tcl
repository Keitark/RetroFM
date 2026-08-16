# Read-only helper for proving the hierarchical object patterns used by the
# full-build CDC gates against the latest routed checkpoint.
set script_dir [file normalize [file dirname [info script]]]
set dcp [file normalize [file join $script_dir ".." "build" "vivado" \
    "retrofm_player" "retrofm_player_routed.dcp"]]
open_checkpoint $dcp
source [file normalize [file join $script_dir ".." "vivado" \
    "cdc_constraints.tcl"]]
retrofm_cdc::apply
foreach {label pattern} [list \
        write_gray_q "*/command_bridge_i/u_jt*_fifo/write_gray_reg*/Q" \
        write_binary_q "*/command_bridge_i/u_jt*_fifo/write_binary_reg*/Q" \
        write_gray_d "*/command_bridge_i/u_jt*_fifo/write_gray_dst_meta_reg*/D" \
        read_gray_q "*/command_bridge_i/u_jt*_fifo/read_gray_reg*/Q" \
        read_binary_q "*/command_bridge_i/u_jt*_fifo/read_binary_reg*/Q" \
        read_gray_d "*/command_bridge_i/u_jt*_fifo/read_gray_src_meta_reg*/D" \
        command_payload_d "*/jt*_i/held_*_reg*/D" \
        sample_payload_d "*/jt*_sample_cdc_i/dst_data_reg*/D" \
        ym_clock_d "*/ym2203_clock_audio_reg*/D" \
        sys_scalar_d "*/reset_request_audio_meta_reg/D" \
        audio_ack_d "*/audio_reset_ack_meta_reg/D" \
        sample_toggle_d "*/jt*_sample_cdc_i/toggle_meta_reg/D"] {
    set objects [get_pins -hier -quiet -filter "NAME =~ $pattern"]
    puts "$label count=[llength $objects] objects=$objects"
}
foreach core {jt51 jt03} {
    set write_dest [get_pins -hier -quiet -filter \
        "NAME =~ */command_bridge_i/u_${core}_fifo/write_gray_dst_meta_reg*/D"]
    set read_dest [get_pins -hier -quiet -filter \
        "NAME =~ */command_bridge_i/u_${core}_fifo/read_gray_src_meta_reg*/D"]
    set write_src [all_fanin -flat -startpoints_only -to $write_dest]
    set read_src [all_fanin -flat -startpoints_only -to $read_dest]
    puts "${core}_write_fanin count=[llength $write_src] objects=$write_src"
    puts "${core}_read_fanin count=[llength $read_src] objects=$read_src"
}
report_exceptions -summary -file [file join $script_dir \
    "inspect_routed_exceptions.rpt"]
foreach port_name {LCD_SCLK LCD_MOSI LCD_CS LCD_DC LCD_RES AUDIO_SD_L AUDIO_SD_R} {
    set port [get_ports -quiet $port_name]
    set port_clocks [get_clocks -quiet -of_objects $port]
    set output_paths [get_timing_paths -quiet -to $port -max_paths 4]
    puts "port=$port_name clocks=$port_clocks timed_paths=[llength $output_paths]"
    foreach path $output_paths {
        puts "  path start=[get_property STARTPOINT_PIN $path] end=[get_property ENDPOINT_PIN $path] slack=[get_property SLACK $path]"
    }
}
close_design
