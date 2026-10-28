# retro-6502

The 6502 sister of [retro-z80](https://github.com/jonsole/retro-z80) and [retro68k](https://github.com/jonsole/retro68k): a 65C02 computer in the FPGA of a **ZX Spectrum Next** (KS2 for bring-up, KS3 for the full machine), for use as a home computer and a games machine. It is retro-z80's chipset with a 65C02 in place of the Z80.

## Goals (version 1)

- **CPU:** 65C02 at 20 MHz; zero page, stack and ROM in fast block RAM, SRAM accesses wait for their data; a vector per interrupt source
- **Memory:** retro-z80's: 4 MB SRAM (2 MB on the KS2) through eight 8 KB MMU windows; 32 KB boot ROM
- **Chipset:** retro-z80's, unchanged: three layers, 8 sprites, the copper, the DMA engine, timers, serial, SD, keyboards, joysticks
- **Registers:** in memory (the 6502 has no I/O space)

## Status

Phase 0: planning. The decisions are in [`docs/design-plan.md`](docs/design-plan.md); start with [`docs/HANDOFF.md`](docs/HANDOFF.md).
