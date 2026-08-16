# EBAZ4205 and expansion-board wiring

## Stereo audio

The logical outputs are `AUDIO_SD_L=P18` and `AUDIO_SD_R=M19`, both LVCMOS33,
slow slew, 4 mA. On the published tomorrow56 adapter schematic these appear on
H4 pin 4 and H4 pin 6 respectively; H4 pin 2 is ground.

The intended connector is **H4**. Before fitting the filter, power the board
off and confirm the published mapping on the assembled board:

| H4 pin | Required continuity |
| --- | --- |
| 4 (left) | FPGA P18 |
| 6 (right) | FPGA M19 |
| 2 (ground) | board ground |

Record the continuity result in `docs/bench-record.md`. Confirm the selected
contacts are not tied to 3.3 V or 5 V.

Each channel is wired:

```text
FPGA output -- 220 ohm --+-- 10 uF series capacitor -- line output
                         |
                       100 nF
                         |
                        GND
```

Connect only to an active speaker or a line input of at least 10 kohm. This is
not a headphone or passive-speaker driver. Observe electrolytic polarity: the
filter side sits near mid-rail under normal sigma-delta audio and is the
positive side unless measurements establish otherwise.

The nominal low-pass corner is `1/(2*pi*220*100 nF) = 7.23 kHz`. A later
47 nF capacitor would move it to approximately 15.4 kHz, but this first build
keeps 100 nF so hardware and simulation describe the same circuit.

## LCD

| Signal | FPGA pin | Note |
| --- | --- | --- |
| CS | T20 | keep asserted during a transaction; it is not backlight |
| D/C | R18 | PS-controlled auxiliary output |
| reset | N17 | PS-controlled auxiliary output |
| SCLK | R19 | PS SPI0 through EMIO |
| MOSI | P20 | PS SPI0 through EMIO |

The validated panel sequence is attributed in `../THIRD_PARTY_NOTICES.md`;
SPI mode 3 and its full ST7789 initialization table are required.

The generated PS configuration reports a 200 MHz SPI peripheral reference.
Target firmware fixes `XSPIPS_CLK_PRESCALE_8`, so this build assumes a
maximum 25 MHz SCLK (40 ns period). Post-synthesis constraints require each
direct PS7-EMIO-to-package route to stay below 12 ns and require SCLK/MOSI
relative route skew below 1 ns, with exact two-startpoint/two-endpoint and
one-path-per-signal gates. Vivado cannot apply `set_bus_skew` to these
combinational PS7-to-output paths, so the build hard-gates the difference of
the two routed `DATAPATH_DELAY` values at 1 ns. These checks cover the FPGA PL
routes only. ST7789
setup/hold at the display, adapter/cable delay, ringing, and voltage margin
remain bench-provisional until measured at R19/P20 and the panel connector.

## SD card

Standalone operation requires the expansion-board microSD/TF slot. Use an
8 GB or 16 GB microSDHC card for first bring-up; ordinary Class 4 or Class 10
is sufficient. Cards from 4 GB through 32 GB are reasonable candidates, but
larger/faster SDXC media have poorer compatibility on this adapter and add no
playback benefit.

Create one MBR primary partition and format it FAT32 (32 KB allocation units
are a safe choice). Do not use exFAT and do not leave recovery or secondary
partitions on the card. Copy the contents of `build/vitis/sd` to the root:

```text
/BOOT.BIN
/BUILD-MANIFEST.json
/music/*.mdx, *.pdx, *.vgm, *.vgz
/testdata/...
```

`BOOT.BIN` must be in the root. The player recursively scans `/music` to four
directory levels. Set MIO5 to the verified SD-boot level before a power cycle;
MIO4 is not a player button and should not be held during reset.

## Bring-up measurements

1. With the FPGA unconfigured, verify P18, M19, and the selected H4 contacts'
   voltages.
2. Load the mute-only bitstream. Both audio pins must remain within 0..3.3 V.
3. Load the fixed-tone diagnostic and verify H4 L/R continuity and channel
   identity before connecting the filter.
4. Measure after the 10 uF capacitor: less than 50 mV DC after settling.
5. Use a high-impedance oscilloscope to check rail overshoot and channel
   isolation. Simulation without an IBIS/package/interconnect model cannot
   prove the overshoot requirement.
