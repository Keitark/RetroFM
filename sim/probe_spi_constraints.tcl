# Read-only isolated proof of the direct PS7 SPI0 output constraint contract
# against the latest routed checkpoint. reset_timing removes the older
# checkpoint's broad output false path before applying the current contract.
set script_dir [file normalize [file dirname [info script]]]
set sample_dir [file normalize [file join $script_dir ".."]]
set dcp [file join $sample_dir "build" "vivado" "retrofm_player" \
    "retrofm_player_routed.dcp"]
open_checkpoint $dcp
reset_timing -invalid
source [file join $sample_dir "vivado" "io_constraints.tcl"]
retrofm_io::apply
set report_dir [file join $sample_dir "build" "vivado" "retrofm_player" \
    "reports"]
retrofm_io::check_routed [file join $report_dir \
    "spi_constraint_probe_timing.rpt"]
report_exceptions -summary -file [file join $report_dir \
    "spi_constraint_probe_exceptions.rpt"]
close_design
