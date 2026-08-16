# Standalone build and SD packaging

Run from the repository root:

```powershell
.\samples\retrofm_player\packaging\build_firmware.ps1
```

The script verifies every pinned dependency, creates a fresh Vitis standalone
platform from the routed XSA, enables FatFs long filenames, discovers the AXI
base and interrupt from generated `xparameters.h`, compiles the application
with Vitis ARM GCC, obtains the platform FSBL, invokes Bootgen, and verifies the
rights-cleared test files.

Successful output is under `../build/vitis`:

- `artifacts/build-manifest.json`: compiler, XSA, address/IRQ, DDR, and hashes;
- `artifacts/retrofm_app.elf` and `retrofm_fsbl.elf`;
- `sd/BOOT.BIN`: Zynq boot image;
- `sd/music`: the six CC0 smoke-test files (three MDX, one PDX, one VGM,
  and one VGZ);
- `sd/BUILD-MANIFEST.json`: a copy of the exact build receipt.

Copy the contents of `sd`, not the `sd` directory itself, to the root of a
single-partition FAT32 microSD/TF card. Packaging success is not evidence of a
physical cold boot or audible playback.
