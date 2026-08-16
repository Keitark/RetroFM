# Xilinx standalone application boundary

`main.c` is the complete target-side integration point. It intentionally is
not part of the host CMake project because it requires generated headers and
libraries from an integrated hardware platform.

Required build inputs:

- an XSA containing the RetroFM AXI peripheral and bitstream;
- a `ps7_cortexa9_0` standalone BSP with `xilffs`, `XSpiPs`, `XScuGic`, UART,
  `sleep`, and the generated `xparameters.h`;
- compile definition `RETROFM_HW_BASEADDR` set to the generated AXI base;
- compile definition `RETROFM_IRQ_ID` set to the generated F2P interrupt ID;
- `RETROFM_HAS_VGZ=1` plus the pinned miniz tinfl source/configuration used by
  the host core build.

Compile `main.c`, `../retrofm_st7789.c`, `../retrofm_ui.c`,
`../retrofm_diagnostic.c`, and every source in `../../core/src`. Include `..`,
`../../core/include`, and the BSP include directory. Link against the
standalone BSP and miniz tinfl library.

The application performs these bounded operations:

- recursively scans `0:/music` to four directory levels and finalizes the
  host-tested playlist;
- validates MDX/PDX or the complete single-YM2203 VGM stream before unmute;
- decompresses one bounded VGZ gzip member into a fixed 8 MiB buffer;
- prefills and services the 2048-event and 4096-frame PCM FIFOs;
- keeps the IRQ handler write-free: it only requests main-context refill, so
  no second writer can interleave the staged `EVENT_LO`/`EVENT_HI` commit;
- renders the ST7789 at the M5StickS3 33 ms cadence (50 ms with PCM8) through
  bounded 32-row slices at 25 MHz, keeping each blocking transfer comfortably
  inside the roughly 85 ms PCM FIFO service window;
- edge-detects the debounced active-high button levels and implements previous,
  play/pause, next, volume down, and volume up;
- persists the volume step in `0:/retrofm-volume.cfg`;
- auto-advances only after the parser has ended, the software event queue has
  drained, and `EVENT_STATUS[22]` reports the scheduler halted.

The checked-in packaging flow now generates the standalone BSP with
`xilffs use_lfn=1`, selects the exact address and interrupt macros from
`xparameters.h`, compiles every target/core/miniz translation unit with Vitis
ARM GCC, links the application and generated FSBL, and packages `BOOT.BIN`.
See `../../../STATUS.md` and `../../../build/vitis/artifacts/build-manifest.json`
for the released build receipt. This does not claim that the image has booted
or produced audio on a physical board.
