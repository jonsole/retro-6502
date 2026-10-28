# Spec 7: System

Status: **draft**

This spec covers how retro-6502 starts: reset, the boot ROM, identification and the CPU speed. retro-6502 uses **retro-z80's spec 7** (`retro-z80/docs/spec/system.md`) for everything else: the reset sources and what survives a reset, the writable boot ROM, the boot console, the buttons, the I2C master, installing on the Next and the board connections. This spec lists only what the 65C02 changes, in the same order. Where the two disagree, this spec wins for retro-6502.

## 1. Summary

| Item | Value |
|------|-------|
| Board | As retro-z80: the KS2 (XC7A15T, 2 MB) for bring-up, the KS3 (XC7A35T, 4 MB) for the full machine |
| After reset | 65C02 at 10 MHz; it reads its reset vector at `$FFFC` from boot ROM page 3 in window 7. Windows 0–6 = SRAM pages 0–6, window 7 = ROM page 3 (section 4.2) |
| CPU speed | CPUSPEED: a cycle every n slots, n = 1–10: 10, 5, 3.33, 2.5, 2, 1.67, 1.43, 1.25, 1.11, 1 MHz (section 6.1) |
| Identification | SYSID `0x36` ("6"); SYSCFG.CPU = 1 (65C02) (section 6) |
| Registers | retro-z80's system control and I2C registers `0x70`–`0x7B` of the system block, at `$FE70`–`$FE7B` (spec 1, section 6.1) and register page offsets `0x0070`–`0x007B` |
| Spectrum extras | None. No NMI monitor paging, no port `0xFE` and so no beeper in version 1 (section 10) |

## 2. Comparison with retro-z80

| retro-z80 (spec 7) | retro-6502 | Why |
|--------------------|------------|-----|
| Z80 starts at `0x0000`; windows 0–1 = ROM pages 0–1, windows 2–7 = SRAM pages 0–5 | 65C02 starts through its reset vector at `$FFFC`; windows 0–6 = SRAM pages 0–6, window 7 = ROM page 3 | The 6502 needs RAM at `$0000`–`$01FF` and its vectors at `$FFFA`–`$FFFF` (design plan, branch 3) |
| 20 MHz after reset; CPUSPEED DIV (2–0) and SPECTRUM (3) | 10 MHz after reset; CPUSPEED DIV (3–0), n = DIV + 1 slots a cycle | Spec 1, section 3.1; design plan, branch 6 |
| SYSID `0x5A` ("Z"); SYSCFG.CPU = 0 | SYSID `0x36` ("6"); SYSCFG.CPU = 1 | Design plan, branch 9 |
| Registers reached through ports `0x7000`–`0x7B00` | At `$FE70`–`$FE7B` | No I/O space (spec 1, section 6.1) |
| Reset held for at least 28 clocks (a T-state at 3.57 MHz) | At least 100 clocks (a cycle at 1 MHz) | The slowest speed |
| The boot ROM assembled with sjasmplus | With ca65 and ld65 | Design plan, branch 3 |
| IM 2 with the ROM's own table | Plain IRQs (INTCON.VECTOR clear); a vector table at `$FFD0`–`$FFFF` in ROM page 3 for programs that turn VECTOR on with VECBASE = `0xD0` | Spec 1, section 7.1; design plan, branch 10 |
| Boot file `BOOT.Z80` | `BOOT.65` (open point SY2) | – |
| BBC BASIC (Z80) | BBC BASIC (6502) if a licence is found, else Microsoft's 6502 BASIC (design plan, branch 4) | – |
| NMI monitor paging; the beeper on port `0xFE` bit 4 | Neither (section 10) | Spectrum extras; port `0xFE` is not built |

## 3. Reset

### 3.2 What a reset does

As retro-z80, except:

- The 65C02 is reset and reads its reset vector at `$FFFC`–`$FFFD`, at **10 MHz** (CPUSPEED = `0x00`). Its reset sequence makes no writes (spec 1, section 2.1), so the SRAM keeps every byte.
- The MMU goes back to the reset state of section 4.2.
- There are no interrupt pages, so nothing of retro-z80's NMI set is reset.

### 3.3 Power-on sequence

As retro-z80, with the 65C02 in place of the Z80: the system reset is released at the start of a slot, so the CPU's first cycle starts on slot edge 0 (spec 1, section 8). At every later reset, reset is held for at least **100 system clocks** (one cycle at 1 MHz, the slowest speed) and released at the start of a slot.

### 3.4 No RESET instruction

The 65C02 has none either; a program that wants clean hardware writes SYSRESET (`$FE75`).

## 4. Boot ROM

### 4.1 The ROM

As retro-z80: 32 KB of block RAM in the bitstream, seen as MMU pages `0x3FC`–`0x3FF`, writable for development with SYSCON.ROMWE. The build assembles it with **ca65** and links it with **ld65**, whose configuration places each segment in its ROM page.

### 4.2 Mapping at reset

| Window | Addresses | Read and write page |
|--------|-----------|---------------------|
| 0–6 | `$0000`–`$DFFF` | SRAM pages `0x000`–`0x006` |
| 7 | `$E000`–`$FFFF` | `0x3FF`: boot ROM page 3 (ROM offsets `0x6000`–`0x7FFF`) |

So the 65C02 has zero page, the stack and 56 KB of RAM below the ROM, and the ROM's last 8 KB on top, ending with the vectors, as 6502 ROMs do. ROM offsets `0x7E00`–`0x7EFF` lie under the `$FE00` page in window 7 (spec 1, section 6.1): the ROM puts no code there that must run from window 7, though another window can still map page 3 and read those bytes. Pages 0–2 are reached by mapping them into a window.

ROM page 3 holds, at its top:

| Address in window 7 | ROM offset | Contents |
|---------------------|------------|----------|
| `$FFD0`–`$FFF9` | `0x7FD0`–`0x7FF9` | The IRQ vector table, sources 0–20, used with INTCON.VECTOR set and VECBASE = `0xD0` (spec 1, section 7.1) |
| `$FFFA`–`$FFFB` | `0x7FFA` | NMI vector (table entry 21) |
| `$FFFC`–`$FFFD` | `0x7FFC` | Reset vector (entry 22) |
| `$FFFE`–`$FFFF` | `0x7FFE` | IRQ/BRK vector (entry 23, NONE: a spurious IRQ) |

An operating system that maps SRAM into window 7 copies this table and the vectors into its own page.

## 5. What the boot ROM does

As retro-z80's outline (its spec 7, section 5, and spec 16), with these changes:

- Step 4: set up the stack (S = `$FF`, page 1), every source off, INTCON.VECTOR clear; the ROM polls and starts no timer tick. Its table at `$FFD0` is there for programs that set VECBASE = `0xD0` and VECTOR.
- Step 9: the boot file is **`BOOT.65`** (open point SY2), and BASIC is BBC BASIC (6502) if it can be licensed, otherwise Microsoft's 6502 BASIC (design plan, branch 4).
- The monitor and the debug link are retro-z80's, with the 65C02's registers (A, X, Y, S, P, PC) in place of the Z80's (design plan, branch 4); spec 16 is still to be written.

## 6. Identification and CPU speed

**SYSID** reads **`0x36`** ("6"). **SYSCFG.CPU** (bits 1–0) is **1**: the 65C02. retro-z80 keeps 0 for the Z80; 2 and 3 are kept for later CPUs. SYSCFG.CHIPMB is as retro-z80 (2 on the KS2, 4 on the KS3). One program can tell the machines apart by SYSID alone, or by SYSCFG.CPU.

### 6.1 CPU speed

| CPUSPEED | DIV (3–0) | A cycle every | Speed |
|----------|-----------|---------------|-------|
| `0x00` | 0 | 1 slot (10 clocks) | **10 MHz** (after reset) |
| `0x01` | 1 | 2 slots | 5 MHz |
| `0x02` | 2 | 3 slots | 3.33 MHz |
| `0x03` | 3 | 4 slots | 2.5 MHz |
| `0x04` | 4 | 5 slots | **2 MHz** (BBC Micro) |
| `0x05` | 5 | 6 slots | 1.67 MHz |
| `0x06` | 6 | 7 slots | 1.43 MHz |
| `0x07` | 7 | 8 slots | 1.25 MHz |
| `0x08` | 8 | 9 slots | 1.11 MHz |
| `0x09` | 9 | 10 slots | **1 MHz** (Apple II, C64, the BBC Micro's slow bus) |
| `0x0A`–`0x0F` | 10–15 | 10 slots | 1 MHz, as `0x09` |

- **DIV** (bits 3–0) = n − 1: a cycle every n slots. Every speed is locked to the slots: every cycle starts on slot edge 0 (spec 1, section 3.1). There is no Spectrum speed.
- Bits 7–4 read 0 and ignore writes. DIV reads back as written, also for 10–15.
- A change takes effect at the cen edge after the write: the next cycle runs at the new speed (spec 1, section 3.1). CPUSPEED is `0x00` after every reset.

```
        lda  #$04               ; DIV = 4: a cycle every 5 slots
        sta  CPUSPEED           ; $FE77: 2 MHz from the next cycle
```

## 10. Spectrum extras

None in retro-6502:

- **NMI monitor paging:** not in version 1 (spec 1, open point B6). The NMI button and USB BREAK run the NMI vector of whatever page window 7 maps; the boot ROM's points at the monitor.
- **The beeper:** retro-z80's beeper is bit 4 of port `0xFE`, which retro-6502 does not build (`$FEFE` reads `0xFF`, spec 1, section 6.1). So version 1 has no sound until spec 13, unless a beeper bit is added (open point SY13).

## 11. Registers

retro-z80's registers `0x70`–`0x7B`, at **`$FE70`–`$FE7B`** (spec 1, section 6.1) and at register page offsets `0x0070`–`0x007B`. The same bits and reset values, except:

| Register | Address | Name | Change |
|----------|---------|------|--------|
| `0x70` | `$FE70` | SYSID | Reads `0x36` ("6") |
| `0x72` | `$FE72` | SYSCFG | CPU (1–0) reads 1 |
| `0x77` | `$FE77` | CPUSPEED | DIV (3–0): a cycle every DIV + 1 slots (section 6.1); bits 7–4 read 0. No SPECTRUM bit |

`0x7C`–`0x7F` are free, as in retro-z80. Writing a 2-byte register here is not needed: every system control register is one byte.

## 12. FPGA resources

As retro-z80, less the beeper and its three sigma-delta modulators (about 280 LUTs) while there is no sound, and less the Spectrum speed in the clock enable.

## 13. Test plan

As retro-z80's, with these changes:

- **Reset state:** after every reset the 65C02 reads `$FFFC` from ROM offset `0x7FFC`, runs at 10 MHz with every cycle on slot edge 0; MMU0–MMU7 read `0x000`–`0x006` and `0x3FF`; no SRAM byte changes across any reset but power-on, including page 1.
- **Registers:** SYSID reads `0x36` and SYSCFG.CPU 1 at `$FE70` and `$FE72` and at register page offsets `0x0070` and `0x0072`.
- **CPU speed:** every CPUSPEED value gives its cycle spacing (10n clocks, `0x0A`–`0x0F` as `0x09`); the change happens at the next cen edge; every cycle on slot edge 0; both of Klaus Dormann's tests pass at 10 MHz and 1 MHz on the system.
- **Vectors in ROM:** after reset every IRQ reads `$FFFE`; with VECTOR set and VECBASE = `0xD0` the boot ROM's table at `$FFD0`–`$FFFF` gives each source in use its handler.
- Left out: the NMI paging and beeper tests, and the 3.57 MHz tests.

## 14. Open points

| # | Item |
|---|------|
| SY2 | The boot file's name (`BOOT.65` proposed) and the shared image header's CPU field, to agree with retro-z80 and retro68k (shared monitor spec) |
| SY13 | A beeper before sound (spec 13): add a one-bit beeper register in the system block (in `0x7C`–`0x7F`, free), or wait for spec 13 |
| SY14 | Spec 16 (boot ROM and monitor) for the 65C02: the start-up steps in ca65, the monitor's register display and commands with A, X, Y, S, P, PC, and the debug stub |
| SY15 | Whether retro-z80's own items carry over unchanged: the KS3 core format (its SY4), the real-time clock (SY9), Ctrl + Alt + Delete (SY10), the console font (SY12) |
