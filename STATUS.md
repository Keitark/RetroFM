# RetroFM candidate status

Checked 2026-08-16. This is an evidence ledger for the source candidate, not a
promise of intended features. A result is marked only when the named artifact
or test exists in the audit workspace.

The public snapshot is deliberately source-only. It contains no build
directory, binary hash table, BOOT.BIN, bitstream, ELF, or private music.

## Candidate evidence

| Gate | Current result | Evidence |
| --- | --- | --- |
| Host core tests | PASS, 9/9 public CTest tests | Reproduce with `test.ps1` |
| Target-support tests | PASS, 3/3 public CTest tests | Reproduce with `test.ps1`; the private prototype adds one non-public comparison test |
| Baseline RTL suites | Scripted by verify.ps1; candidate RTL sources and testbenches are present | verify.ps1 and sim/ |
| OPNA RTL source path | Candidate source includes the JT2608 wrapper, OPNA activity meters, and bounded ADPCM-B sample RAM | rtl/vendor/retrofm_jt2608_wrapper.v, rtl/retrofm_opna_activity.sv, rtl/retrofm_opna_adpcmb_ram.sv |
| Full candidate route | PASS; routed setup slack +0.122 ns, hold slack +0.052 ns, DRC 0 errors | Reproduce with `verify.ps1 -ImplementFullDesign` |
| Routed package | PASS; bitstream and XSA were created for the candidate | Public snapshot intentionally omits those artifacts |
| Firmware package | Candidate receipt exists; public snapshot intentionally omits the package | Private-prototype packaging is blocked by default |
| Physical board | OPEN | docs/bench-record.md |

Re-run the commands in README.md to recreate the checks from the pinned inputs.

## Implemented candidate scope

- MDX with optional PDX PCM through the JT51 YM2151-compatible hardware path.
- One-chip YM2203 VGM/VGZ through the JT03-compatible hardware path.
- Experimental one-chip YM2608 VGM/VGZ through the JT2608 path.
- OPNA candidate audio includes six FM lanes, SSG, and ADPCM-B from an optional
  same-stem sidecar capped at 128 KiB.
- Fixed YM2608 rhythm-ROM/ADPCM-A audio is not implemented.
- The event/mixer/delta-sigma plane uses 100 MHz; the JT51 path uses the exact
  4 MHz YM2151 enable in the 80 MHz Yamaha-core domain.

## Packaging and redistribution boundary

The public tree contains source, scripts, documentation, and deterministic
rights-cleared test fixtures only. Do not describe a source checkout as a
ready-to-flash board image. A locally generated firmware package must retain
the dependency locks, license notices, and per-file rights records.

## Analog and physical acceptance

- [x] Analytic 220 ohm / 100 nF corner recorded as approximately 7.23 kHz.
- [ ] Standalone ngspice AC/transient evidence.
- [ ] H4-4/H4-6/H4-2 continuity to P18/M19/ground.
- [ ] Audio pins remain within 0..3.3 V before the filter.
- [ ] Settled post-capacitor DC is below 50 mV.
- [ ] Overshoot and channel isolation measured with a high-impedance probe.
- [ ] Fixed JT51 tone heard through both filtered outputs.
- [ ] MDX-only playback heard and accepted.
- [ ] MDX plus PDX playback heard and accepted.
- [ ] YM2203 VGM and VGZ playback heard and accepted.
- [ ] Experimental YM2608 playback heard and accepted.
- [ ] ST7789 display and five buttons accepted.
- [ ] FAT32 cold SD boot accepted.
- [ ] Thirty-minute playback remains free of underrun, late-event, and fault
      counters.

No physical-board item may be inferred from simulation, synthesis, routing,
packaging, or a successful host test.
