# SPDX-License-Identifier: GPL-3.0-or-later
# Scoped physical constraints for the RetroFM 100/80 MHz CDC structures.
# Source this from ordinary build Tcl after synth_design; this is deliberately
# not an XDC file because endpoint cardinality checks require procedural Tcl.

namespace eval retrofm_cdc {}

proc retrofm_cdc::require_pins {description pattern expected_count} {
    set pins [get_pins -hier -quiet -filter "NAME =~ $pattern"]
    set actual_count [llength $pins]
    if {$actual_count != $expected_count} {
        error "RetroFM CDC $description resolved $actual_count pins, expected $expected_count ($pattern): $pins"
    }
    return $pins
}

proc retrofm_cdc::launch_cells {description destinations expected_count} {
    set startpoints [all_fanin -flat -startpoints_only -to $destinations]
    set cells [get_cells -quiet -of_objects $startpoints]
    set actual_count [llength $cells]
    if {$actual_count != $expected_count} {
        error "RetroFM CDC $description resolved $actual_count launch cells, expected $expected_count: $cells"
    }
    return $cells
}

proc retrofm_cdc::apply {} {
    set system_clock [get_clocks -quiet clk_fpga_0]
    set audio_clock [get_clocks -quiet \
        clk_out1_retrofm_system_audio_clock_0]
    if {[llength $system_clock] != 1 || [llength $audio_clock] != 1} {
        error "RetroFM explicit 100/80 MHz clocks did not resolve: system=$system_clock audio=$audio_clock"
    }

    foreach core {jt51 jt03} {
        set write_dest [retrofm_cdc::require_pins \
            "$core FIFO write Gray destination" \
            "*/command_bridge_i/u_${core}_fifo/write_gray_dst_meta_reg*/D" 4]
        set read_dest [retrofm_cdc::require_pins \
            "$core FIFO read Gray destination" \
            "*/command_bridge_i/u_${core}_fifo/read_gray_src_meta_reg*/D" 4]
        set write_src [retrofm_cdc::launch_cells \
            "$core FIFO write Gray source" $write_dest 4]
        set read_src [retrofm_cdc::launch_cells \
            "$core FIFO read Gray source" $read_dest 4]

        set_max_delay -datapath_only 10.000 \
            -from $write_src -to $write_dest
        set_bus_skew 10.000 -from $write_src -to $write_dest
        set_max_delay -datapath_only 10.000 \
            -from $read_src -to $read_dest
        set_bus_skew 10.000 -from $read_src -to $read_dest
    }

    set command_payload_dest [concat \
        [retrofm_cdc::require_pins \
            "JT51/JT03 FIFO command payload" "*/jt*_i/held_*_reg*/D" 32] \
        [retrofm_cdc::require_pins \
            "YM2608 FIFO command payload" "*/opna_i/held_*_reg*/D" 17]]
    set sample_payload_dest [concat \
        [retrofm_cdc::require_pins "JT sample mailbox payload" \
            "*/jt*_sample_cdc_i/dst_data_reg*/D" 48] \
        [retrofm_cdc::require_pins "OPNA sample mailbox payload" \
            "*/opna_sample_cdc_i/dst_data_reg*/D" 32]]
    # JT51, JT03 and OPNA contribute 32 + 16 + 32 physical sample bits.
    # Values above 80 MHz are sanitized to the 4 MHz default in the source
    # domain, so the five high constant-zero bits are optimized away.  All 27
    # physically meaningful configuration bits are required here.
    set ym2203_clock_dest [retrofm_cdc::require_pins \
        "YM2203 reset-handshake config" "*/ym2203_clock_audio_reg*/D" 27]
    set scalar_system_to_audio [retrofm_cdc::require_pins \
        "system-to-audio scalar synchronizer" \
        "*/reset_request_audio_meta_reg/D" 1]
    set audio_ack_dest [retrofm_cdc::require_pins \
        "audio reset acknowledgement" "*/audio_reset_ack_meta_reg/D" 1]
    set sample_toggle_dest [retrofm_cdc::require_pins \
        "sample toggle synchronizers" \
        "*/jt*_sample_cdc_i/toggle_meta_reg/D" 2]
    set active_chip_dest [retrofm_cdc::require_pins \
        "OPN chip selection synchronizer" \
        "*/active_chip_audio_meta_reg*/D" 2]

    # The command RAM word is held from the source write until the
    # destination acknowledges consumption.  The synchronized Gray pointer
    # cannot expose it for at least two 80 MHz destination clocks (25 ns).
    # A 20 ns datapath bound therefore preserves the bundled-data contract
    # while avoiding a false single-cycle requirement between unrelated
    # system/audio clocks.  The tighter 10 ns bus-skew limit above remains.
    set_max_delay -datapath_only 20.000 \
        -from $system_clock -to $command_payload_dest
    set_max_delay -datapath_only 10.000 \
        -from $audio_clock -to $sample_payload_dest
    set_max_delay -datapath_only 10.000 \
        -from $system_clock -to $ym2203_clock_dest
    set_max_delay -datapath_only 10.000 \
        -from $system_clock -to $active_chip_dest
    set_false_path -from $system_clock -to $scalar_system_to_audio
    set_false_path -from $audio_clock \
        -to [concat $audio_ack_dest $sample_toggle_dest]

    puts "RETROFM_CDC_CONSTRAINTS_APPLIED gray_dest=16 command_payload=49 sample_payload=80 ym_clock=27 active_chip=2 scalar=4"
}
