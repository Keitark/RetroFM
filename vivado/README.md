# Vivado build notes

The PS block design is regenerated from tomorrow56's `ps_setting.tcl` instead
of trusting a binary XSA. The script then overrides FCLK0 from 50 to 100 MHz,
keeps SD0 on MIO40..45 with card detect on MIO34, enables M_AXI_GP0 and the
fabric interrupt, and exports SPI0 through EMIO.

The generated PS SPI pins must be connected explicitly:

- `SPI0_SCLK_O` to top-level `LCD_SCLK` / R19;
- `SPI0_MOSI_O` to top-level `LCD_MOSI` / P20;
- `SPI0_SS_O` or a GPIO-controlled CS to `LCD_CS` / T20;
- auxiliary GPIO outputs to `LCD_DC` / R18 and `LCD_RES` / N17.

The preset produces a 200 MHz PS SPI reference and target firmware selects
prescaler 8, limiting SCLK to 25 MHz. `io_constraints.tcl` proves the exact
two PS7 hard-IP startpoints and package endpoints, bounds each direct PL route
to 12 ns, and hard-gates measured routed SCLK/MOSI datapath skew to 1 ns.
Vivado does not support a `set_bus_skew` endpoint on this combinational PS7
hard-IP-to-output path. These are FPGA-route checks;
external ST7789 setup/hold remains a scope/bench acceptance item.

Do not reuse the archived tomorrow56 LCD netlist: its SPI clock and MOSI outputs
were left unconnected. Do not add an external clock constraint: the PL domain
is sourced by PS `FCLK_CLK0` and constrained by the generated PS clock object.

The final design uses a Clocking Wizard to derive an exact 80 MHz Yamaha-core
clock from FCLK0. JT51 fails an ordinary 100 MHz single-cycle OOC timing check;
do not hide that with blanket multicycle exceptions. AXI, event deadlines,
mixing, and the 1-bit outputs remain at 100 MHz.

`..\build.ps1` is the supported one-command hardware build. It first runs
`create_project.tcl`, which regenerates and signs off the complete routed
design and writes its DCP/BIT. It then starts a second Vivado process with
`package_routed.tcl`; that script reopens the exact routed checkpoint, repeats
the timing, CDC, route, I/O, and exception gates, and writes the bit-bearing
XSA. This two-process export is required because the in-process implementation
flow has no implementation-run object for Vivado 2024.2
`write_hw_platform` to query. A build is packaged only after the
`RETROFM_ROUTED_PACKAGE_PASS` marker appears.
