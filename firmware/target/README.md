# Standalone target firmware

This directory is the target integration boundary. Portable parsing, playlist
and player state, CP932 title conversion, sequencing, and ADPCM decoding live
in `../core`; Xilinx BSP calls stay in `xilinx/main.c`.

The standalone application is built by `../../packaging/build_firmware.ps1`.
The released 2026-08-13 platform export provides:

- `xilffs`/FatFs on PS SD0 (MIO40..45, card detect MIO34);
- `XSpiPs` SPI0 through EMIO for the ST7789;
- the RetroFM AXI peripheral and low-water/fault interrupt;
- a UART console for bring-up diagnostics.

The real generated receipt selected `XPAR_RETROFM_PL_BASEADDR=0x43C00000`,
`XPAR_FABRIC_RETROFM_PL_IRQ_INTR=61U`, and `FILE_SYSTEM_USE_LFN=1`. The
application ELF, generated FSBL, and `BOOT.BIN` are recorded in
`../../STATUS.md`. They are build evidence only; target boot and playback are
still physical acceptance items.

## Boot sequence

1. Configure the PL and keep the mixer muted.
2. Mount FAT32 and enumerate supported files below `/music`.
3. Initialize the ST7789 in SPI mode 3 using the complete table attributed in
   `../../THIRD_PARTY_NOTICES.md`.
4. Validate the selected file completely enough to reject unsupported chips,
   clocks, commands, and offsets before unmute.
5. Reset/flush both hardware FIFOs, configure the active core clock, prefill
   event and PCM queues, issue START, then ramp unmute.
6. Refill on low water. Any event underrun, overflow, or late event is a track
   error and causes a mute/error screen.

The IRQ handler never writes an event. It only disables the source and asks the
main loop to refill, preserving a single writer for the staged event commit.
`retrofm_hw_event_push()` writes `EVENT_LO`, executes an ARM `dmb sy`, writes
the commit word `EVENT_HI`, then executes another barrier. The application uses
an explicit completion barrier before enabling `CONTROL.RUN`.

`retrofm_diagnostic.c` supplies a host-tested fixed JT51 tone: channel 0 pans
left, channel 1 pans right, both use conservative attenuation, key off after
500 ms, and emit END after a 50 ms release interval. It is a bring-up artifact;
it has not been heard on the board.

MDX integration must use the clean pinned mdxtools subset and all hardening
listed in `../../docs/dependency-audit.md`; upstream mdxtools is not copied here
unchanged because its parsers are not bounds-safe.
