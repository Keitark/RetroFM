################################################################################
# EBAZ4205 RetroFM external PL pins
# Target: xc7z010clg400-1, PL banks at 3.3 V
################################################################################

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# Stereo 1-bit sigma-delta output on expansion header H4.
# H4-4 = P18 (left), H4-6 = M19 (right), H4-2 = ground.
set_property PACKAGE_PIN P18 [get_ports AUDIO_SD_L]
set_property PACKAGE_PIN M19 [get_ports AUDIO_SD_R]
set_property IOSTANDARD LVCMOS33 [get_ports {AUDIO_SD_L AUDIO_SD_R}]
set_property DRIVE 4 [get_ports {AUDIO_SD_L AUDIO_SD_R}]
set_property SLEW SLOW [get_ports {AUDIO_SD_L AUDIO_SD_R}]

# ST7789. T20 is chip select, not a backlight.
set_property PACKAGE_PIN T20 [get_ports LCD_CS]
set_property PACKAGE_PIN R18 [get_ports LCD_DC]
set_property PACKAGE_PIN N17 [get_ports LCD_RES]
set_property PACKAGE_PIN R19 [get_ports LCD_SCLK]
set_property PACKAGE_PIN P20 [get_ports LCD_MOSI]
set_property IOSTANDARD LVCMOS33 [get_ports {LCD_CS LCD_DC LCD_RES LCD_SCLK LCD_MOSI}]
set_property DRIVE 4 [get_ports {LCD_CS LCD_DC LCD_RES LCD_SCLK LCD_MOSI}]
set_property SLEW SLOW [get_ports {LCD_CS LCD_DC LCD_RES LCD_SCLK LCD_MOSI}]

# Five switches on the adapter have schematic pull-ups and close to ground.
set_property PACKAGE_PIN T19 [get_ports {BUTTON_N[0]}]
set_property PACKAGE_PIN P19 [get_ports {BUTTON_N[1]}]
set_property PACKAGE_PIN U20 [get_ports {BUTTON_N[2]}]
set_property PACKAGE_PIN U19 [get_ports {BUTTON_N[3]}]
set_property PACKAGE_PIN V20 [get_ports {BUTTON_N[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {BUTTON_N[*]}]
set_property PULLUP true [get_ports {BUTTON_N[*]}]

# BUTTON_N is intentionally asynchronous and terminates only at the first
# synchronizer stage.  The outputs do not have an external synchronous capture
# relationship: audio is a pulse-density stream and CS/D-C/reset are static
# controls.  LCD SCLK/MOSI are deliberately excluded here: their direct PS7
# EMIO routes receive explicit max-delay and pair-skew constraints after
# synthesis.  False-path only the asynchronous/static package-port arcs; all
# internal clocked paths remain timed.
set_false_path -from [get_ports {BUTTON_N[*]}]
set_false_path -to [get_ports {AUDIO_SD_L AUDIO_SD_R \
    LCD_CS LCD_DC LCD_RES}]

# Cross-domain endpoint discovery, cardinality gates, and scoped CDC timing
# exceptions are applied from create_project.tcl after synthesis. Vivado's XDC
# reader intentionally supports only declarative constraints, not Tcl proc/if.

# Leave the Ethernet, NAND, and every unclaimed ball high impedance.
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLNONE [current_design]
