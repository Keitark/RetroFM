# Event-driven YM2203 playback and meters

```mermaid
flowchart LR
    SD["SD card: VGM / VGZ"] --> PARSE["ARM: decompress and parse"]
    PARSE --> FIFO["Timestamped event FIFO"]
    FIFO --> SCHED["100 MHz deadline scheduler"]
    SCHED -->|"register write at musical deadline"| OBS["YM2203 meter observer"]
    SCHED --> BRIDGE["100 to 80 MHz command bridge"]
    BRIDGE --> JT03["JT03: YM2203 FM + SSG"]
    JT03 --> MIX["48 kHz stereo mixer"]
    MIX --> SDM["L/R sigma-delta outputs"]

    OBS --> FM["FM1-3: key-on + OP4 total level"]
    OBS --> SSG["SSG1-3: amplitude + mixer + envelope restart"]
    FM --> CAPTURE["Current state + captured volume + sticky trigger"]
    SSG --> CAPTURE
    CAPTURE --> AXI["AXI ABI 1.1 meter registers"]
    AXI --> UI["ARM UI: note kick, decay, afterglow"]
    UI --> LCD["ST7789 six-part meter"]
```

The observer is driven by the register write emitted at the hardware playback
deadline, not by the parser. Consequently, SD reading, gzip decompression, and
FIFO preloading cannot make the display run ahead of the audible JT03 output.

MDX and VGM/VGZ now share the same UI animation. Their volume sources differ:
MXDRV supplies its logical part volume for MDX, while the YM2203 observer uses
operator 4 total level for FM and the amplitude/envelope setting for SSG.
