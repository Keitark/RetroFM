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
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 validation_axi_sink
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 validation_axi_ic
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 validation_reset
set_property CONFIG.NUM_MI {1} [get_bd_cells validation_axi_ic]

# The preset owns DDR, fixed I/O, NAND, UART, and SD0 MIO40..45/CD MIO34.
source $preset_file
set ps_config [apply_preset [get_bd_cells ps7]]
dict set ps_config CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}
dict set ps_config CONFIG.PCW_CLK0_FREQ {100000000}
dict set ps_config CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ {100.000000}
dict set ps_config CONFIG.PCW_USE_FABRIC_INTERRUPT {1}
dict set ps_config CONFIG.PCW_IRQ_F2P_INTR {1}
dict set ps_config CONFIG.PCW_USE_M_AXI_GP0 {1}
set_property -dict $ps_config [get_bd_cells ps7]
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_CLK0_FREQ {100000000} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
] [get_bd_cells ps7]

# PS7's exported fixed interfaces are required by the FSBL and standalone BSP.
make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]

# Temporary AXI slave keeps this board-preset validation design structurally
# complete. The integrated build replaces it with the RetroFM AXI peripheral.
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] \
    [get_bd_intf_pins validation_axi_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins validation_axi_ic/M00_AXI] \
    [get_bd_intf_pins validation_axi_sink/S_AXI]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] \
    [get_bd_pins ps7/M_AXI_GP0_ACLK] \
    [get_bd_pins validation_axi_ic/ACLK] \
    [get_bd_pins validation_axi_ic/S00_ACLK] \
    [get_bd_pins validation_axi_ic/M00_ACLK] \
    [get_bd_pins validation_axi_sink/s_axi_aclk] \
    [get_bd_pins validation_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] \
    [get_bd_pins validation_reset/ext_reset_in]
connect_bd_net [get_bd_pins validation_reset/peripheral_aresetn] \
    [get_bd_pins validation_axi_ic/ARESETN] \
    [get_bd_pins validation_axi_ic/S00_ARESETN] \
    [get_bd_pins validation_axi_ic/M00_ARESETN] \
    [get_bd_pins validation_axi_sink/s_axi_aresetn]

# SPI0 is a master. Its EMIO SS input must be inactive when no external master
# exists, otherwise the PS controller can spuriously enter slave mode.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 spi_ss_inactive
set_property CONFIG.CONST_VAL {1} [get_bd_cells spi_ss_inactive]
connect_bd_net [get_bd_pins spi_ss_inactive/dout] [get_bd_pins ps7/SPI0_SS_I]
assign_bd_address

# The complete custom AXI peripheral is connected by create_project.tcl after
# its packaged IP is available. Keeping this script separate makes the board
# preset auditable before a generated IP repository exists.

validate_bd_design
save_bd_design
