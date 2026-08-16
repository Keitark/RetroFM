# SPDX-License-Identifier: GPL-3.0-or-later
# Post-synthesis physical contract for direct PS7 SPI0 EMIO LCD outputs.

namespace eval retrofm_io {}

proc retrofm_io::resolve {} {
    set sclk_source [get_pins -hier -quiet -filter \
        {NAME =~ */PS7_i/EMIOSPI0SCLKO}]
    set mosi_source [get_pins -hier -quiet -filter \
        {NAME =~ */PS7_i/EMIOSPI0MO}]
    set sclk_port [get_ports -quiet LCD_SCLK]
    set mosi_port [get_ports -quiet LCD_MOSI]
    foreach {description objects} [list \
            "SPI0 SCLK PS7 startpoint" $sclk_source \
            "SPI0 MOSI PS7 startpoint" $mosi_source \
            "LCD SCLK package endpoint" $sclk_port \
            "LCD MOSI package endpoint" $mosi_port] {
        if {[llength $objects] != 1} {
            error "RetroFM I/O $description resolved [llength $objects] objects: $objects"
        }
    }

    # Prove that the two named PS7 hard-IP outputs are the sole timing
    # startpoints feeding their corresponding package ports.
    set sclk_fanin [all_fanin -flat -startpoints_only -to $sclk_port]
    set mosi_fanin [all_fanin -flat -startpoints_only -to $mosi_port]
    if {[llength $sclk_fanin] != 1 || [lindex $sclk_fanin 0] ne $sclk_source} {
        error "LCD_SCLK startpoint mismatch: expected=$sclk_source actual=$sclk_fanin"
    }
    if {[llength $mosi_fanin] != 1 || [lindex $mosi_fanin 0] ne $mosi_source} {
        error "LCD_MOSI startpoint mismatch: expected=$mosi_source actual=$mosi_fanin"
    }

    set sclk_paths [get_timing_paths -quiet -from $sclk_source \
        -to $sclk_port -max_paths 2]
    set mosi_paths [get_timing_paths -quiet -from $mosi_source \
        -to $mosi_port -max_paths 2]
    set cross_paths [concat \
        [get_timing_paths -quiet -from $sclk_source -to $mosi_port \
            -max_paths 1] \
        [get_timing_paths -quiet -from $mosi_source -to $sclk_port \
            -max_paths 1]]
    if {[llength $sclk_paths] != 1 || [llength $mosi_paths] != 1 || \
            [llength $cross_paths] != 0} {
        error "SPI timing-path cardinality mismatch: sclk=[llength $sclk_paths] mosi=[llength $mosi_paths] cross=[llength $cross_paths]"
    }
    return [list [list $sclk_source $mosi_source] \
        [list $sclk_port $mosi_port]]
}

proc retrofm_io::apply {} {
    lassign [retrofm_io::resolve] spi_sources spi_ports

    # The generated PS preset provides a 200 MHz SPI reference, and firmware
    # fixes the controller prescaler at 8 (25 MHz SCLK, 40 ns period).
    # These constraints bound only the two direct PL routes; external ST7789
    # setup/hold, adapter, and cable timing remain bench-verification items.
    # Vivado cannot apply set_bus_skew to this PS7 combinational-output to
    # package-output path. Route both signals against an explicit fraction of
    # the 80 ns serial period; check_routed then measures pair skew directly.
    set_max_delay -datapath_only 12.000 \
        -from [lindex $spi_sources 0] -to [lindex $spi_ports 0]
    # P20/MOSI is physically the slower of the pair.  A 10 ns route has
    # already been demonstrated on this device and forces implementation to
    # preserve the independently checked <=1 ns SCLK/MOSI pair skew.
    set_max_delay -datapath_only 10.000 \
        -from [lindex $spi_sources 1] -to [lindex $spi_ports 1]
    puts "RETROFM_SPI_IO_CONSTRAINTS_APPLIED startpoints=2 endpoints=2 sclk_max_delay_ns=12.000 mosi_max_delay_ns=10.000 measured_pair_skew_limit_ns=1.000 spi_ref_mhz=200 prescaler=8 sclk_mhz=25"
}

proc retrofm_io::check_routed {report_path} {
    lassign [retrofm_io::resolve] spi_sources spi_ports
    set sclk_path [get_timing_paths -quiet -from [lindex $spi_sources 0] \
        -to [lindex $spi_ports 0] -delay_type max -max_paths 1]
    set mosi_path [get_timing_paths -quiet -from [lindex $spi_sources 1] \
        -to [lindex $spi_ports 1] -delay_type max -max_paths 1]
    if {[llength $sclk_path] != 1 || [llength $mosi_path] != 1} {
        error "Routed SPI paths did not resolve one-to-one: sclk=$sclk_path mosi=$mosi_path"
    }
    report_timing -from $spi_sources -to $spi_ports -delay_type max \
        -max_paths 2 -file $report_path
    set sclk_slack [get_property SLACK $sclk_path]
    set mosi_slack [get_property SLACK $mosi_path]
    set sclk_delay [get_property DATAPATH_DELAY $sclk_path]
    set mosi_delay [get_property DATAPATH_DELAY $mosi_path]
    set pair_skew [expr {abs(double($sclk_delay) - double($mosi_delay))}]
    if {$sclk_slack < 0.0 || $mosi_slack < 0.0} {
        error "Routed SPI max-delay failed: sclk_slack=$sclk_slack mosi_slack=$mosi_slack"
    }
    if {$pair_skew > 1.000} {
        error "Routed SPI pair skew failed: sclk_delay=$sclk_delay mosi_delay=$mosi_delay skew=$pair_skew ns"
    }
    puts "RETROFM_SPI_IO_ROUTE_PASS sclk_delay_ns=$sclk_delay mosi_delay_ns=$mosi_delay pair_skew_ns=$pair_skew sclk_slack_ns=$sclk_slack mosi_slack_ns=$mosi_slack"
}
