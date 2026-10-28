# FPGA RTL

Plain Verilog-2005, linted with Verilator (`sh fpga/lint.sh`; WIDTHTRUNC is an error) and simulated with Verilator in `sim/`. Chip-specific parts are in `platform/artix7/`, simulation versions in `platform/sim/`. Most modules are retro-z80's chipset, copied from a committed, tested state: [PROVENANCE.md](PROVENANCE.md) lists each one's origin and changes.

| File | What | Spec |
|------|------|------|
| `retro6502.v` | The computer without board parts: timebase, reset, the 65C02, memory, registers, serial, interrupts, video, copper, timers, input | 1, 7 |
| `bus6502.v` | The bus interface: the clock enable (a cycle every n slots, on slot edge 0), AB/WE/DO/DUMMY sampled at E + 2, SRAM in cycle 2, boot ROM, the register page and the `$FE00` page, DUMMY reads skipped, the IRQ response watcher and the vector table, the CPU's capture | 1 |
| `mmu.v` | retro-z80's MMU with retro-6502's reset map (windows 0–6 SRAM pages 0–6, window 7 ROM page 3) | 7, section 4.2 |
| `intc.v` | retro-z80's interrupt controller with INTCON.VECTOR (bit 1) | 1, section 7.1 |
| `sysregs.v` | retro-z80's system registers: SYSID `0x36`, SYSCFG.CPU = 1, CPUSPEED DIV (3–0) | 7 |
| The rest | retro-z80's units, unchanged: `dmac.v`, `sram_ctl.v`, `timebase.v`, `bootrom.v`, `serial.v`, `fifo8.v`, `timers.v`, `video.v`, `bpldma.v`, `layer_pix.v`, `sprites.v`, `sprite_pix.v`, `copper.v`, `keys.v`, `joy.v`, `ps2kb.v`, `ps2map.v`, `tmds_encoder.v`, `regmap.vh` | retro-z80's specs |
