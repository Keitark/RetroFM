# SPDX-License-Identifier: GPL-3.0-or-later
# Complete EBAZ4205 PS/PL block design.  Project sources, including the
# retrofm_pl_top module reference, must be loaded before sourcing this file.

set script_dir [file normalize [file dirname [info script]]]
set sample_dir [file normalize [file join $script_dir ".."]]
set preset_file [file normalize [file join $sample_dir "build" "deps" \
    "tomorrow56" \
    "cq_pub" "02_z7000_ps" "files" \
    "ps_setting.tcl"]]

if {![file exists $preset_file]} {
    error "EBAZ4205 PS preset not found: $preset_file"
}

create_bd_design "retrofm_system"
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7

# The tomorrow56 preset is the board source of truth for DDR, NAND, UART1,
# and SD0.  Only the PL clock, AXI master, interrupt, and unused EMIO GPIO are
# deliberately overridden here.
source $preset_file
set ps_config [apply_preset [get_bd_cells ps7]]
dict set ps_config CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}
dict set ps_config CONFIG.PCW_CLK0_FREQ {100000000}
dict set ps_config CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ {100.000000}
dict set ps_config CONFIG.PCW_USE_FABRIC_INTERRUPT {1}
dict set ps_config CONFIG.PCW_IRQ_F2P_INTR {1}
dict set ps_config CONFIG.PCW_USE_M_AXI_GP0 {1}
dict set ps_config CONFIG.PCW_EN_EMIO_GPIO {0}
dict set ps_config CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {0}
set_property -dict $ps_config [get_bd_cells ps7]
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_CLK0_FREQ {100000000} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_EMIO_GPIO {0} \
    CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {0}] [get_bd_cells ps7]

# Lock the timing assumption shared by the firmware and the post-synthesis
# LCD serial-output constraints. The target sets XSPIPS_CLK_PRESCALE_8, so a
# 200 MHz PS SPI reference produces a maximum 25 MHz SCLK.
set spi_ref_mhz [get_property CONFIG.PCW_ACT_SPI_PERIPHERAL_FREQMHZ \
    [get_bd_cells ps7]]
if {[expr {abs(double($spi_ref_mhz) - 200.0)}] > 0.001} {
    error "Expected 200 MHz PS SPI reference, found $spi_ref_mhz MHz"
}
if {[get_property CONFIG.PCW_EN_EMIO_SPI0 [get_bd_cells ps7]] ne "1"} {
    error "PS SPI0 must be routed through EMIO"
}
puts "RETROFM_PS_SPI_CONTRACT ref_mhz=$spi_ref_mhz prescaler=8 sclk_mhz=25"

make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic
set_property CONFIG.NUM_MI {1} [get_bd_cells axi_ic]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset_system
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 audio_clock
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {80.000} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_LOW}] [get_bd_cells audio_clock]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset_audio

create_bd_cell -type module -reference retrofm_pl_bd retrofm_pl

connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] \
    [get_bd_intf_pins axi_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ic/M00_AXI] \
    [get_bd_intf_pins retrofm_pl/S_AXI]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] \
    [get_bd_pins ps7/M_AXI_GP0_ACLK] \
    [get_bd_pins axi_ic/ACLK] \
    [get_bd_pins axi_ic/S00_ACLK] \
    [get_bd_pins axi_ic/M00_ACLK] \
    [get_bd_pins reset_system/slowest_sync_clk] \
    [get_bd_pins audio_clock/clk_in1] \
    [get_bd_pins retrofm_pl/s_axi_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] \
    [get_bd_pins reset_system/ext_reset_in] \
    [get_bd_pins audio_clock/resetn]
connect_bd_net [get_bd_pins reset_system/peripheral_aresetn] \
    [get_bd_pins axi_ic/ARESETN] \
    [get_bd_pins axi_ic/S00_ARESETN] \
    [get_bd_pins axi_ic/M00_ARESETN] \
    [get_bd_pins retrofm_pl/s_axi_aresetn]

connect_bd_net [get_bd_pins audio_clock/clk_out1] \
    [get_bd_pins reset_audio/slowest_sync_clk] \
    [get_bd_pins retrofm_pl/clk_audio]
connect_bd_net [get_bd_pins audio_clock/locked] \
    [get_bd_pins reset_audio/dcm_locked]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] \
    [get_bd_pins reset_audio/ext_reset_in]
connect_bd_net [get_bd_pins reset_audio/peripheral_reset] \
    [get_bd_pins retrofm_pl/rst_audio]

# SPI0 is a unidirectional master for the ST7789.  CS, D/C, and RESET_N are
# driven by LCD_AUX in the RetroFM AXI peripheral; no PS GPIO EMIO is needed.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_zero
set_property CONFIG.CONST_VAL {0} [get_bd_cells const_zero]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_one
set_property CONFIG.CONST_VAL {1} [get_bd_cells const_one]
connect_bd_net [get_bd_pins const_zero/dout] \
    [get_bd_pins ps7/SPI0_SCLK_I] \
    [get_bd_pins ps7/SPI0_MOSI_I] \
    [get_bd_pins ps7/SPI0_MISO_I]
connect_bd_net [get_bd_pins const_one/dout] [get_bd_pins ps7/SPI0_SS_I]
connect_bd_net [get_bd_pins ps7/SPI0_SCLK_O] \
    [get_bd_pins retrofm_pl/lcd_sclk_from_ps]
connect_bd_net [get_bd_pins ps7/SPI0_MOSI_O] \
    [get_bd_pins retrofm_pl/lcd_mosi_from_ps]

connect_bd_net [get_bd_pins retrofm_pl/irq] [get_bd_pins ps7/IRQ_F2P]

foreach {name direction pin} [list \
        AUDIO_SD_L O audio_sd_l \
        AUDIO_SD_R O audio_sd_r \
        LCD_CS O lcd_cs \
        LCD_DC O lcd_dc \
        LCD_RES O lcd_res \
        LCD_SCLK O lcd_sclk \
        LCD_MOSI O lcd_mosi] {
    create_bd_port -dir $direction $name
    connect_bd_net [get_bd_ports $name] [get_bd_pins retrofm_pl/$pin]
}
create_bd_port -dir I -from 4 -to 0 BUTTON_N
connect_bd_net [get_bd_ports BUTTON_N] [get_bd_pins retrofm_pl/button_n]

set slave_segments [get_bd_addr_segs -quiet retrofm_pl/S_AXI/*]
if {[llength $slave_segments] != 1} {
    error "Expected one RetroFM AXI address segment, found: $slave_segments"
}
assign_bd_address -offset 0x43C00000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces ps7/Data] \
    [lindex $slave_segments 0] -force

validate_bd_design
save_bd_design
