# retro-6502 design plan

Status: **draft**. Decisions are made one by one (section 1).

retro-6502 is the 6502 sister of [retro-z80](https://github.com/jonsole/retro-z80) (design plan, branch 8) and [retro68k](https://github.com/jonsole/retro68k). It runs on the same board with the same chipset as retro-z80. Only the CPU, its bus interface, the memory map seen by the CPU and the firmware differ.

## 1. Decision tree

| # | Branch | Decision |
|---|--------|----------|
| 1 | Repo | Its own repo, a sister machine (retro-z80 branch 8, Q2) |
| 1 | When | Started now, alongside retro-z80 |
| 1 | CPU | **65C02** (CMOS instruction set; no undocumented NMOS opcodes) |
| 1 | Interrupt vectors | **The interrupt controller answers the vector fetch:** on a hardware IRQ response, the reads of `$FFFE`/`$FFFF` return VECBASE + 2 × source, so each source has its own vector, as IM 2 gives the Z80 |
| 1 | Chipset | retro-z80's, copied from a committed, tested state: video, sprites, copper, DMA engine, scheduler, SRAM controller, MMU, interrupt controller, timers, serial, SD, keyboards, joysticks |
| 1 | Board | As retro-z80: the KS2 for bring-up, the KS3 for the full machine |
| 2 | CPU core | **Arlet Ottens' Verilog 65C02**, once its licence and exactness are checked (a 65C02 test suite in simulation) |
| 2 | Register window | **`$FE00`–`$FEFF`**, one page just below the vectors, never paged out (as the BBC Micro's SHEILA). It reaches the system block, so the MMU works from reset; the full blocks are reached through the register page, as on retro-z80 |
| 2 | BRK against IRQ | **The bus interface spots the IRQ response from outside the core** and only then makes the controller answer the `$FFFE`/`$FFFF` reads; BRK reads the ROM's vector |

## 2. Known differences from retro-z80

| retro-z80 | retro-6502 | Why |
|-----------|------------|-----|
| tv80, 20 MHz, a memory access every 3–4 T-states | 65C02, a memory access every clock; with the CPU's two cycles per slot (0 and 2) up to 20 MHz with no waits | 6502 |
| Registers in I/O space (register:page ports) and in the register page | Registers in memory only: a register window always mapped, from reset | The 6502 has no I/O space, and the MMU must be reachable before anything is mapped |
| IM 2 vectors from the controller on the acknowledge | The controller answers the `$FFFE`/`$FFFF` reads of an IRQ response | The 6502 has one IRQ vector |
| Window 0 holds the boot ROM at reset | RAM at `$0000`–`$01FF` (zero page, stack) and ROM with the vectors at `$FFFA`–`$FFFF` after reset | 6502 |
| Spectrum extras: port `0xFE`, Kempston `0x1F`, the attribute layer, NMI monitor paging | Left out (the attribute layer to be decided) | No Spectrum software to port |
| Interrupt pages, stack capture, debug unit (`intpages.v`, `dbgunit.v`) | To be redesigned for the 6502's response and RTI | Z80-specific |
| sjasmplus, BBC BASIC (Z80) | To be decided | 6502 |

## 3. Open questions

| # | Item | Plan |
|---|------|------|
| Q1 | Arlet's 65C02 core | Chosen (branch 2). To check: licence, exactness (a 65C02 test suite), RDY, and how its bus timing (read data the clock after the address) fits the slots |
| Q2 | Memory map seen by the CPU | Register window `$FE00`–`$FEFF` (branch 2). Still open: what window 0 (zero page, stack) and window 7 (ROM, vectors) hold at reset, and how the register page in `$FE00` is laid out (256 bytes for the system block's `0x00`–`0xFF`) |
| Q3 | IRQ response against BRK | Closed (branch 2): the bus interface spots the response. To specify in spec 1: which cycles it watches (the response has no opcode fetch before its pushes), and NMI's `$FFFA` |
| Q4 | Assembler | ca65 (cc65) or 64tass |
| Q5 | BASIC | BBC BASIC for the 6502 (licence to check) or EhBASIC |
| Q6 | CPU speeds | retro-z80's CPUSPEED divider, or a 6502 set (for example 1 and 2 MHz for old timing) |
| Q7 | Monitor, upload and debug link | retro-z80's shared monitor and debug specs with a 6502 register set |
