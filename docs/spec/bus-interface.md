# Spec 1: CPU bus interface

Status: **draft**

This spec connects the 65C02 to everything else. It covers how the core is clocked and how its speed is set, how its memory cycles become requests on the internal chipset buses, how each access is fitted into the CPU's memory cycle so that the 6502 never waits, how the registers are reached without an I/O space, and how interrupts, NMI and reset work.

It follows retro-z80's spec 1, with the 65C02 in place of tv80. The memory side (the 100 MHz clock, slots, the scheduler, the SRAM controller, the MMU, the register page) is retro-z80's spec 2, used unchanged (design plan, branch 6). The registers are retro-z80's spec 3. Why the top speed is 10 MHz is in `docs/notes/why-10-mhz.md`.

## 1. Summary

| Item | Value |
|------|-------|
| CPU | `cpu_65c02.v` (hoglet67's verilog-6502: Arlet Ottens' 6502 core with 65C02 extensions), with a clock enable added (section 2) |
| Clock | The 100 MHz system clock, with one clock enable (cen): a CPU cycle per cen pulse |
| CPU speed | A cycle every n slots, n = 1–10: 10, 5, 3.33, 2.5, 2, 1.67, 1.43, 1.25, 1.11 or 1 MHz. 10 MHz after reset. Every cycle starts on slot edge 0. Set by CPUSPEED |
| Memory | Every cycle is one access. Every access goes through the MMU (retro-z80 spec 2): reads to the window's read page, writes to its write page. An SRAM access uses the CPU's **cycle 2** of the slot the CPU cycle starts in; boot ROM and register accesses use none |
| Wait states | None, ever. RDY is tied high (section 5) |
| Registers | No I/O space. **`$FE00`–`$FEFF` is the system block**, register n at `$FE00` + n, over whatever window 7 maps (design plan, branch 4). Everything else (the custom block, the palettes, the other I/O pages) through the register page, mapped into a window (section 6) |
| Register bus | retro-z80's: 8-bit, one clock per access; masters the copper (first), the CPU, the sprite sequencer, the DMA engine (last) (section 4.2) |
| Interrupts | IRQ from the interrupt controller (retro-z80 spec 8). In an IRQ response the bus interface sends the two vector reads to a table entry chosen by the source: `$FF00` + VECBASE + 2 × source and the byte after it, in place of `$FFFE` and `$FFFF`. BRK reads `$FFFE` as normal (section 7) |
| NMI | From the interrupt controller (button, USB BREAK); the core's own vector at `$FFFA` (section 7.3) |
| Reset | The first cycle starts on slot edge 0; the core reads its reset vector at `$FFFC` from boot ROM page 3 in window 7 (section 8) |
| Not used | RDY (tied high); the core has no SO, VPB, ML, BE or WAI/STP |

### 1.1 Comparison with retro-z80

| retro-z80 (spec 1) | retro-6502 | Why |
|--------------------|------------|-----|
| tv80, 20 MHz: a T-state every 5 clocks, a memory access every 3 or more T-states | 65C02, 10 MHz: a cycle every 10 clocks (one slot), a memory access in every cycle | A 6502 often builds its next address from the byte just read, so a read must come back within one cycle; the CPU's turns on the 20 ns grid are 40 and 60 ns apart, never a steady 50 (`docs/notes/why-10-mhz.md`) |
| Speeds 20 MHz ÷ n (n = 1–8) and 3.57 MHz | 10 MHz ÷ n (n = 1–10): every speed locked to the slots | 2 MHz and 1 MHz for BBC Micro and C64 timing; no Spectrum speed (design plan, branch 6) |
| The CPU uses cycle 0 or 2, by T-state phase; at most one a slot | The CPU uses cycle 2 of the slot each cycle starts in, never cycle 0 | Every CPU cycle starts on slot edge 0 (section 5.2). Cycle 0 always goes to the free pool |
| Writes posted to the next CPU cycle after T2 | Writes made in the cycle's own cycle 2, and done before the next CPU cycle | The core gives the write's address and data together, early in the cycle |
| I/O ports in register:page form; both blocks also in the register page | No I/O space: the system block at `$FE00`–`$FEFF`, fixed; the rest through the register page | The 6502 has no I/O instructions; the MMU must be reachable from reset (design plan, branch 4) |
| An opcode fetch from the register page gives `0xFF` and no strobe | No special case: the bus cannot tell a fetch from a read before the cycle ends | The core gives no early cycle type (section 6.4) |
| IM 2: the controller puts VECBASE + 2 × source on the bus in the acknowledge; I is the table's high byte | The two vector reads of an IRQ response go to `$FF00` + VECBASE + 2 × source, through window 7 | The 6502 has one IRQ vector and no acknowledge cycle; the table is in the page the vectors are in (section 7.1) |
| IM 1: `RST 38h`, the handler reads INTID | The same idea is BRK's vector at `$FFFE`: with VECBASE = `0xD0` a spurious IRQ uses it too | 6502 |
| NMI at `0x0066`; NMI monitor paging; interrupt pages and stack capture | NMI through its own vector at `$FFFA`; no paging, no capture in version 1 (open point B6) | retro-z80 extras built round the Z80's response cycles |
| Refresh cycles ignored | None | The 6502 has no refresh |
| HALT waits for an interrupt | No WAI or STP in the core | `cpu_65c02.v` |

## 2. The core

### 2.1 The changes

retro-6502 keeps its copy of `cpu_65c02.v` in `fpga/third_party/verilog-6502/`. It already differs from hoglet67's in two ways (`fpga/rtl/PROVENANCE.md`): D is cleared on BRK, IRQ, NMI and reset, and `IMPLEMENT_CORRECT_BCD_FLAGS` is defined. This spec adds one more:

- **cen.** A clock enable input. Every `always @(posedge clk)` block in the core and its ALU acts only on clocks where cen is high, so the core does one cycle per cen pulse, as tv80 does one T-state per cen pulse in retro-z80. The core's own RDY (which also pauses it) is tied high. RDY is not used as the enable: the core takes read data into DIHOLD on the first clock RDY is low, which assumes the byte arrives the clock after the address, as from block RAM.

The core is otherwise unchanged. Klaus Dormann's 6502 functional test and 65C02 extended opcodes test must still pass with cen pulsed (section 11).

### 2.2 Signals

| Signal | Dir. | Use here |
|--------|------|----------|
| clk | in | 100 MHz system clock |
| cen | in | Clock enable: one clock high per CPU cycle (section 3) |
| reset | in | System reset (retro-z80 spec 7), section 8 |
| RDY | in | Tied high: the 6502 never waits |
| IRQ | in | From the interrupt controller: high while an enabled source is pending (its int_n inverted) |
| NMI | in | From the interrupt controller; the core takes a rising edge |
| AB[15:0] | out | Address. Combinational: it settles after the cen edge that starts the cycle, and in many cycles depends on DI (section 5.1) |
| WE | out | 1 = this cycle writes. Combinational, like AB |
| DO[7:0] | out | Write data. Combinational |
| DI[7:0] | in | Read data: the byte read in the **previous** cycle (section 5.1) |
| SYNC | out | High in the cycle after an opcode fetch, while the opcode is on DI. Used by the debug unit, not by the bus interface |

### 2.3 How the core times its accesses

The core is written for synchronous memory: it puts out an address in a cycle, the memory takes it at the edge that ends the cycle, and the byte is on DI during the next cycle. The core uses DI during that next cycle, often to form that cycle's address, and takes it into its registers at the edge that ends it.

So the bus interface acts as the core's synchronous memory, but slowed to the CPU's cycle: it reads the address the core puts out during cycle k, fetches the byte within cycle k, and holds it on DI from the cen edge that starts cycle k + 1 to the one that ends it (section 5).

## 3. Clock enable and speed

### 3.1 Speeds

The core runs on the 100 MHz system clock. A **CPU cycle is one cen pulse**: the core does nothing on clocks where cen is low. cen comes from a slot counter in the bus interface, set by CPUSPEED (retro-z80's register `0x77`, retro-6502's own encoding; spec 7 to be written):

| CPUSPEED | Slots per cycle (n) | Clocks per cycle | 65C02 speed |
|----------|---------------------|------------------|-------------|
| `0x00` (reset) | 1 | 10 | **10 MHz** |
| `0x01` | 2 | 20 | 5 MHz |
| `0x02` | 3 | 30 | 3.33 MHz |
| `0x03` | 4 | 40 | 2.5 MHz |
| `0x04` | 5 | 50 | **2 MHz** (BBC Micro) |
| `0x05` | 6 | 60 | 1.67 MHz |
| `0x06` | 7 | 70 | 1.43 MHz |
| `0x07` | 8 | 80 | 1.25 MHz |
| `0x08` | 9 | 90 | 1.11 MHz |
| `0x09` | 10 | 100 | **1 MHz** (C64, Apple II, BBC Micro's slow bus) |
| `0x0A`–`0xFF` | 10 | 100 | As `0x09`; bits 7–4 read 0 (open point B4) |

- **Locked to the slots:** cen is high on slot edge 0 of every n-th slot, so every CPU cycle starts on slot edge 0, at every speed.
- **Speed changes** take effect at the cen edge after the write to CPUSPEED: the cycle after the write is the first at the new speed. A cycle never changes speed half way through, and no lining up is needed, as every speed is locked to the same slot edge.
- 1 and 2 MHz match those machines' clocks exactly (the C64's PAL clock is 0.985 MHz). Code timed by counting cycles runs at the right speed if the core's cycle counts are a real 65C02's (open point B3).

### 3.2 Timing points

All times in this spec are measured from the cen edge that starts the cycle (call it edge E, always slot edge 0), in clocks of 10 ns. At 10 MHz the next cycle starts at E + 10.

- The core's registers change at E. AB, WE and DO then settle through the core's logic, from its registers and from DI (which the bus interface also changes at E).
- The core takes what it needs from DI, through its logic, into its registers at the next cen edge: E + 10 at 10 MHz, E + 10n at speed n.

### 3.3 Meeting timing at 100 MHz

The core does not run at 100 MHz as a single-clock design, and need not. Every register in the core is enabled by cen, and cen pulses are 10 clocks apart or more, so every path from one core register to another has 100 ns: a 10-clock multicycle path in Vivado, as tv80's paths are 5-clock ones in retro-z80.

The bus interface samples AB, WE and DO at **E + 2**. The paths from the core's registers and from the DI register to these outputs, and on through the MMU's window lookup on AB[15:13], get a 2-clock multicycle constraint (20 ns). DI comes from a bus interface register loaded at E, so the core's paths from DI have the same 10 clocks as its own. Confirming this in Vivado on the KS2's XC7A15T-1 is open point B1.

## 4. The internal chipset buses

The bus interface turns 65C02 cycles into requests on retro-z80's two internal buses (retro-z80 spec 1, section 4), unchanged. Both are plain synchronous buses in the 100 MHz domain and know nothing about the CPU.

### 4.1 Memory port (to the scheduler, retro-z80 spec 2)

The CPU channel of the scheduler (`dmac.v`):

| Signal | Meaning |
|--------|---------|
| cpu_req | A request, held until cpu_ack |
| cpu_we | 1 = write |
| cpu_addr[21:1], cpu_be[1:0] | Physical word address from the MMU and the byte: both for reads, /LB or /UB for a byte write |
| cpu_wdata[15:0] | The byte to write, on both halves |
| cpu_ack | The cycle has been issued |
| cpu_rvalid, rdata[15:0] | Read data, 40 ns after the issue; the bus interface keeps the byte chosen by address bit 0 |

The MMU sends SRAM pages to the scheduler, boot ROM pages to the ROM's block RAM, and answers NONE and reserved pages with `0xFF`. Accesses to the register page (REGS, `0x3F8`) and to `$FE00`–`$FEFF` do not go to the scheduler: they become register bus cycles (section 6).

### 4.2 Register bus

retro-z80's register bus (its spec 1, section 4.2), with the same signals and the same four masters in the same order: the copper, the CPU, the sprite sequencer, the DMA engine. rb_hi is always `0x00` from the CPU here: it carried A15–A8 of an I/O cycle to port `0xFE`, a Spectrum extra retro-6502 does not build. The copper writes at most once every 2 clocks, so the CPU's strobe moves at most one clock; every CPU access has room for it (section 6).

## 5. Memory cycles

### 5.1 What the core does

In every cycle the core either reads (WE = 0) or writes (WE = 1) the address on AB. There is no "no access" cycle: internal cycles also put out an address and read it, and the byte is ignored (section 6.4).

| Point | Read cycle | Write cycle |
|-------|------------|-------------|
| E | The core's registers change; DI changes to the byte of the previous cycle | The same |
| E to E + 2 | AB settles (from the core's registers, or from DI) | AB, WE and DO settle |
| E + 10 (next cen) | The core takes the byte, from DI, at the end of the next cycle (E + 20) | The write must be done before the next cycle reads |

So a read's byte must be at DI **from the cen edge that ends its cycle**, E + 10, and stay there for the whole next cycle.

### 5.2 Which cycle an access uses

Every CPU cycle starts on slot edge 0 (section 3.1), so every access of a 10 MHz cycle falls in the same place in its slot. The CPU owns cycles 0 and 2 of every slot (retro-z80 spec 2, section 4): cycle 0 is issued at the cen edge itself, too early for an address that settles after it, so **every SRAM access uses cycle 2**, issued at slot edge 4. Cycle 0 is never asked for and always goes to the free pool.

| Access | What happens | Then |
|--------|--------------|------|
| Read | Sampled at E + 2; MMU lookup; cpu_req loaded at E + 3; cycle 2 issued at E + 4 | Byte usable at E + 8, loaded into the DI register at E + 10 |
| Write | The same: issued at E + 4 | On the SRAM pins at E + 5 to E + 7, done before the next cycle starts |
| Boot ROM, NONE or reserved page | No SRAM cycle: the ROM's block RAM answers in one clock; NONE and reserved give `0xFF` | Cycle 2 goes to the free pool |
| Register page or `$FE00`–`$FEFF` | No SRAM cycle: a register bus cycle (section 6) | As above |

The page is looked up from the window's read page for a read and its write page for a write.

### 5.3 Timing at 10 MHz

**Read, cycle k starting at slot edge 0 of slot s:**

| Edge | Time (ns) | What happens |
|------|-----------|--------------|
| 0 | 0 | cen. The core's registers change; DI loaded with cycle k − 1's byte |
| 0–2 | 0–20 | AB settles, from the core's registers or from DI |
| 2 | 20 | The bus interface samples AB and WE; MMU lookup on AB[15:13] |
| 3 | 30 | cpu_req loaded, with the page |
| 4 | 40 | **Cycle 2** of slot s issued |
| 5–7 | 50–70 | On the SRAM pins |
| 7 | 70 | Data caught in the input pads |
| 8 | 80 | Byte (picked by A0) ready in the bus interface |
| 10 | 100 | cen: the byte loaded into DI. Cycle k + 1 starts: **2 clocks to spare** |

**Write, cycle k starting at slot edge 0 of slot s:**

| Edge | Time (ns) | What happens |
|------|-----------|--------------|
| 0 | 0 | cen |
| 2 | 20 | AB, WE = 1 and DO sampled; MMU lookup gives the write page |
| 3 | 30 | cpu_req loaded, with the byte on both halves of cpu_wdata |
| 4 | 40 | **Cycle 2** issued |
| 5–7 | 50–70 | On the SRAM pins; /WE low from 55 to 65 ns |
| 10 | 100 | Cycle k + 1 starts; if it reads, its cycle 2 is issued at 140 ns, after the write |

A read that follows a write to the same address therefore always sees the new data.

### 5.4 Slower speeds

At n slots per cycle, the access is made in the first slot exactly as at 10 MHz, and the byte waits in the bus interface until the cen edge at E + 10n. The other slots of the cycle use no CPU memory cycle. A write is on the pins by E + 7, long before the next cycle.

### 5.5 One CPU cycle per slot

At 10 MHz the CPU uses exactly one memory cycle a slot when it runs from SRAM, cycle 2, and none when it runs from the boot ROM or reaches registers. At speed n it uses one in every n slots. Cycle 0 of every slot, and cycle 2 whenever the CPU does not need it, go to the free pool (retro-z80 spec 2, section 4).

### 5.6 Byte data

As retro-z80: the SRAM is 16 bits wide; a read fetches a word and the bus interface keeps the byte chosen by address bit 0; a write drives the byte on both halves and pulls only /LB or /UB low. So the 6502 is little-endian in SRAM, as everywhere else.

## 6. Registers

### 6.1 The `$FE00` page

The 6502 has no I/O space. **`$FE00`–`$FEFF` is the system block**, always, over whatever page window 7 maps (design plan, branch 4): an access there becomes one register bus cycle with rb_addr = `0x0000` + A7–A0, the system page (retro-z80 spec 3). It reaches the interrupt controller (`$FE00`–`$FE0E`), the timers and watchdog (`$FE20`–`$FE4F`), serial (`$FE50`–`$FE57`), SD (`$FE58`–`$FE5F`), keyboard and joysticks (`$FE60`–`$FE6F`), system registers (`$FE70`–`$FE7F`), the MMU (`$FE80`–`$FE9F`) and the geometry unit (`$FEA0`–`$FEBF`). So the MMU can be set from reset, before any window shows the register page.

- The decode is A15–A8 = `0xFE`, before the MMU. A window 7 page is never read or written at `$FE00`–`$FEFF`; a ROM in window 7 keeps that 256-byte hole.
- The Spectrum extras of the system page (Kempston at register `0x1F`, port `0xFE`'s register at `0xFE`) are not built in retro-6502: `$FE1F` and `$FEFE` read `0xFF` and ignore writes.
- Unanswered registers read `0xFF` and ignore writes (rb_hit low).

### 6.2 The register page

Everything else is reached through the register page (REGS, MMU page `0x3F8`, retro-z80 spec 2, section 10), mapped into any window: the custom block at offset `0x1000`, the palettes at `0x1400`–`0x1FFF`, the debug unit at `0x0200`, KEYROW at `0x0100`, and the system block again at `0x0000`. An access to a REGS page becomes one register bus cycle with rb_addr = A12–A0. A read uses the window's read page and a write its write page, as for memory.

### 6.3 Timing

| Access | What the bus interface does (10 MHz) |
|--------|---------------------------------------|
| Read | One rb_rd at E + 3, after AB is sampled at E + 2 and decoded. The data is on rb_rdata at E + 4 (or `0xFF` if rb_hit is low), and loaded into DI at E + 10. If the copper has the bus at E + 3, the strobe moves to E + 4 and the data is ready at E + 5: still 5 clocks to spare |
| Write | One rb_wr at E + 3 with DO (E + 4 if the copper has the bus) |

- **One strobe per cycle.** A cycle that reads a FIFO data register (SERDATA at `$FE53`, SDDATA at `$FE5B`, KBDATA at `$FE62`) takes exactly one byte.
- **Multi-byte values** are at consecutive registers, low byte at the lowest, written directly in any order (retro-z80 spec 3, rule 2), except the MMU pages (commit on the high byte) and the colours (commit on the red byte). `LDA`/`STA` pairs, or `STX` then `STY`, write a 2-byte register low byte first.
- **Live counters** (TIME, COUNT) capture on a read of the low byte, into the CPU's one tagged capture, as retro-z80 (spec 3, rule 4): read the low byte first.

### 6.4 Every cycle is an access

The core puts an address out in every cycle, including internal ones, and gives no signal that a read is real. So the bus interface reads in every cycle with WE = 0, and makes the register bus strobe whenever such a cycle's address is a register. This matters only for registers whose read has a side effect: the FIFO data registers and any register cleared by reading.

What the core puts out in its internal cycles is listed in section 6.5. Known cases, as on a real 6502:

- **Read-modify-write** instructions (`INC`, `DEC`, `ASL`, `LSR`, `ROL`, `ROR`, `TSB`, `TRB`) on a register read it, may read it again, then write it. They are never used on a FIFO data register.
- **Indexed reads that cross a page** may read a wrong address first, in a 6502; whether `cpu_65c02.v` does, and which address, is open point B2.
- An **opcode fetch** from a register (code that runs into `$FE00`–`$FEFF` or the register page by mistake) reads the register; nothing traps it, as the bus cannot tell a fetch until the next cycle (SYNC).

Programs read a FIFO with a plain absolute read (`LDA $FE53`), which makes exactly one read of it.

### 6.5 The core's cycles

To be filled in from `cpu_65c02.v` (open point B2): for each state of the core, whether it reads or writes, and which address it puts out. For example the REG state of an implied instruction puts out the previous cycle's address again (`AB = { ABH, ABL }`), and the PUSH, PULL, JSR, RTS, RTI and BRK states put out stack addresses.

## 7. Interrupts

### 7.1 IRQ

The interrupt controller (retro-z80 spec 8, unchanged) drives IRQ while an enabled source is pending and INTCON.MASTER is set. The core takes it at the end of an instruction if its I flag is clear: it then runs the BRK sequence with the opcode forced to `0x00` and PC not stepped. The **response** is, in order, with nothing between:

| Cycle | IRQ response | BRK instruction |
|-------|--------------|-----------------|
| 1 | The fetch of the next opcode, at PC; the byte is dropped | The fetch of `0x00` |
| 2 | The read at PC again (PC not stepped); the byte is dropped | The read of the byte after it (PC stepped) |
| 3 | Write PC bits 15–8 to the stack | The same |
| 4 | Write PC bits 7–0 to the stack | The same |
| 5 | Write P to the stack, **B (bit 4) = 0** | Write P, **B = 1** |
| 6 | Read `$FFFE` | The same |
| 7 | Read `$FFFF` | The same |

(Cycle counts as the core has them; open point B3.) An NMI response is the same with B = 0 and `$FFFA`/`$FFFB`; reset reads `$FFFC`/`$FFFD`.

**Spotting the response.** The bus interface keeps a count of stack writes in a row (WE = 1, AB in `$0100`–`$01FF`), cleared by any other cycle. The **third** stack write in a row with **bit 4 of DO clear** is the P push of an IRQ or NMI response. Nothing else makes this pattern: BRK pushes B = 1, `JSR` makes two stack writes in a row, `PHA` and `PHP` one.

To tell the IRQ from the NMI at that point, the bus interface keeps a **copy of the core's NMI edge flag**, made by the same rule on the same cen clocks: set by a rising edge of NMI, cleared at the end of a cycle that reads `$FFFA`. The core reads `$FFFA` if its flag is set when it pushes P, and `$FFFE` if not (`cpu_65c02.v`, state BRK2), so with the copy clear the response is an IRQ. Reset also runs this sequence (section 8); the bus interface ignores the first response after a reset, which reads `$FFFC`.

**The vector reads.** At E + 2 of the P push (cycle 5) the bus interface sees an IRQ response and sends **int_vreq** at E + 3. The controller picks the pending source with the lowest number, writes it to INTID, freezes the choice and gives the vector byte v = VECBASE + 2 × source from the next clock (retro-z80 spec 8, sections 3 and 5). In cycle 6 the core reads `$FFFE`; the bus interface puts v in place of A7–A0 as it loads the request: the read goes to **`$FF00` + v**. Cycle 7's read of `$FFFF` goes to `$FF00` + v + 1. After it, the bus interface sends **int_ack**, which ends the freeze. If cycle 6 does not read `$FFFE` (it always does; a check for the testbench), nothing is changed and int_ack is still sent.

The window is window 7 in both reads (A15–A13 do not change), so the MMU lookup is the same as without the change, and both reads are made through window 7's read page. A15–A8 stay `0xFF`: the table is in `$FF00`–`$FFFF`, not in the `$FE00` page.

| Edge | What happens |
|------|--------------|
| Cycle 5, E + 2 | The P push sampled: third stack write, bit 4 clear, NMI copy clear |
| Cycle 5, E + 3 | int_vreq (the push's own write request is loaded as normal) |
| Cycle 5, E + 4 | v ready, held until int_ack |
| Cycle 6, E + 2 | AB = `$FFFE` sampled |
| Cycle 6, E + 3 | cpu_req loaded (or the ROM read made) with address `$FF00` + v |
| Cycle 6, E + 10 | The handler address's low byte on DI |
| Cycle 7 | The same with `$FF00` + v + 1; int_ack at its E + 3 |

So the 6502 reads its handler's address from a **table of 24 two-byte entries** at `$FF00` + VECBASE, one per source number, in whatever page window 7 maps: sources 0–20, two unused entries (21, 22) and NONE (23) for a spurious response. This is IM 2's table in the 6502's vector page.

**VECBASE = `0xD0`** puts the table at `$FFD0`–`$FFFF`, so that entry 21 is the NMI vector (`$FFFA`), entry 22 the reset vector (`$FFFC`) and entry 23, NONE, the ordinary IRQ/BRK vector (`$FFFE`). Sources 0–20 are at `$FFD0`–`$FFF9`. A spurious response (no source pending when the vector is asked for: the program turned the source off in the instruction during which IRQ was sampled) then goes to the BRK handler, which sees B = 0 on the stack and returns. The boot ROM sets VECBASE to `0xD0`; after reset VECBASE is `0x00` and MASTER is off, so no IRQ is taken before it is set.

- The table is wherever window 7 points: in the boot ROM after reset, in SRAM when an operating system maps RAM there and fills its own table.
- **INTID** (`$FE0C`) gives the source of the last response, as in retro-z80.
- The response uses no extra memory cycle and no wait.

### 7.2 BRK

BRK pushes P with B = 1, so the pattern of section 7.1 does not match, and its reads of `$FFFE` and `$FFFF` are ordinary: the BRK handler's address is the window 7 page's own vector at `$FFFE`. With VECBASE = `0xD0` that is also table entry 23.

### 7.3 NMI

The interrupt controller drives NMI from the Multiface-style button and the USB serial BREAK command, as NMICON allows; NMISTAT says which (retro-z80 spec 8, section 10). The core takes a rising edge and runs the NMI response, reading its vector at `$FFFA` and `$FFFB` through window 7. The bus interface changes nothing. It sends **nmi_ack** when it sees the response: the third stack write in a row with bit 4 clear while its copy of the NMI edge flag is set (section 7.1). nmi_ack ends the controller's NMI request (retro-z80 spec 8, section 10).

retro-z80's NMI monitor paging, interrupt pages and stack capture are not in version 1 (open point B6): the NMI goes wherever window 7's vector says, so the monitor is reached only while window 7 shows the boot ROM, or a page with the same NMI vector.

## 8. Reset

- The system reset (retro-z80 spec 7) drives the core's reset. The MMU, the speed (back to 10 MHz) and the bus interface reset together with the core.
- Reset is released so that the core's first cycle starts on **slot edge 0**, as in retro-z80. Simulations then match the board cycle for cycle.
- After reset windows 0–6 are SRAM pages `0x000`–`0x006` and window 7 is **boot ROM page 3** (`0x3FF`, ROM offsets `0x6000`–`0x7FFF`), read and write (design plan, branch 3). So the 6502 reads its reset vector from ROM offset `0x7FFC`: the ROM image ends with its vectors, as 6502 ROMs do. Zero page and the stack are in SRAM page 0.
- The core runs reset as its BRK sequence, and `cpu_65c02.v` makes its three stack pushes as real writes (WE = 1 in BRK0–BRK2), to wherever S points, where a real 6502 makes them reads. So a reset changes three bytes of page 1 of whatever SRAM window 0 maps (open point B8).
- The core has no RESET output; a soft reset is a write to SYSRESET (`$FE75`, retro-z80 spec 7).

## 9. Things the core does not have

- **RDY:** tied high. No access ever needs a wait.
- **WAI, STP, BBR, BBS, RMB, SMB:** not in `cpu_65c02.v`. Their opcodes are NOPs of the 65C02's lengths.
- **SO:** not in the core; the V flag is set only by instructions.
- **Bus sharing:** none. The chipset uses its own memory cycles.

## 10. FPGA resources

| Item | Resource |
|------|----------|
| `cpu_65c02.v` | About 800–1,200 LUTs, no block RAM (to be measured on the KS2) |
| Bus interface: cen divider, request timing, `$FE00` decode, register bus master, the response watcher and vector path | Estimate 150–250 LUTs |

## 11. Test plan

- **Core with cen:** Klaus Dormann's 6502 functional test and 65C02 extended opcodes test pass in `sim/cputest` with cen pulsed every 10 clocks, and give the same cycle count as with cen always high.
- **Speeds:** at every CPUSPEED setting, count clocks per cycle (10n); every cen falls on slot edge 0; a change takes effect at the next cen edge.
- **No waits:** run code from SRAM at every speed with the display (layers at their budget, urgent fetches), sprites, the copper and the DMA engine all busy; check that every access is issued in cycle 2 of its cycle's first slot, that the CPU never asks for cycle 0, and that the byte is ready before the cen edge that loads it into DI.
- **Writes:** byte writes to even and odd addresses change only that byte; a read in the next cycle sees the new data.
- **Read and write pages:** in a split window, reads use the read page and writes the write page, at all speeds.
- **`$FE00` page:** every system register at `$FE00` + n gives the same value as at its register page offset; a window 7 page is never touched at `$FE00`–`$FEFF`; one strobe per access, also with a copper write in the same clock; `$FE1F`, `$FEFE` and unanswered registers read `0xFF`.
- **Register page:** reads and writes through REGS in any window give one strobe each; a FIFO read with `LDA abs` takes one byte.
- **IRQ vectors:** with VECBASE = `0xD0` and `0x00`, each source in use reaches its handler through its table entry; INTID agrees; one int_vreq and one int_ack per response. A spurious response reads entry 23. BRK reads `$FFFE` itself. `JSR`, `PHA` of a byte with bit 4 clear, reset and an NMI give no int_vreq. An NMI edge during an IRQ response's pushes makes the core read `$FFFA`: the copy of the NMI flag agrees, and no int_vreq is sent.
- **NMI:** from the button and from USB BREAK, the core reads `$FFFA`; nmi_ack is sent once.
- **Instruction tests on the whole system:** the functional and extended tests from SRAM and from the boot ROM, at 10 MHz and 1 MHz, with the system testbench's never-waited checks.
- **Reset:** the first cycle after every reset starts on slot edge 0; the core reads `$FFFC` from ROM offset `0x7FFC` and runs at 10 MHz.

## 12. Open points

| # | Item |
|---|------|
| B1 | Timing in Vivado on the KS2 (XC7A15T-1): the core's paths as 10-clock multicycle paths, and AB, WE, DO through the MMU's window lookup in 2 clocks (section 3.3) |
| B2 | List every state of `cpu_65c02.v` with its access (read or write) and address (section 6.5), and find which cycles make reads a program did not ask for: page-crossing indexed reads, the second read of a read-modify-write, internal cycles. If any can hit a FIFO data register in a way programs cannot avoid, bring out a "real read" signal from the core |
| B3 | Cycle counts: check `cpu_65c02.v` against a real 65C02 instruction by instruction (a 65C02's decimal `ADC` and `SBC` take one more cycle than a 6502's; its read-modify-write and page-crossing cycles differ from the NMOS part). Exact counts matter at 1 and 2 MHz |
| B4 | CPUSPEED's encoding for retro-6502 (n − 1 in bits 3–0, values above 9 acting as 9) and whether SYSCFG.CPU = 1 names the 65C02. Both are in spec 7, still to be written from retro-z80's |
| B5 | The IRQ vector table (section 7.1) is a proposal that refines design plan branch 1 ("the reads of `$FFFE`/`$FFFF` return VECBASE + 2 × source"): the controller's byte becomes the low byte of a table entry's address in `$FFxx`, as IM 2 uses it, so each source has a full 16-bit handler address. To confirm |
| B6 | retro-z80's extras for the NMI and interrupts (the NMI monitor paging, interrupt pages, stack capture) and its debug unit (spec 18): which retro-6502 needs, and how each would spot the 6502's response and return (`RTI`) from outside the core. The debug link (design plan, branch 4) needs the debug unit; SYNC gives it the start of each instruction |
| B7 | Whether the CPU's spare cycle 0 could read ahead the byte at PC + 1 for instruction fetches, as a later speed-up (`docs/notes/why-10-mhz.md`, N1) |
| B8 | Reset pushes (section 8): `cpu_65c02.v` writes three bytes to the stack in its reset sequence. retro-z80 keeps the SRAM across resets so a debugger can look at what a crashed program left. Either suppress WE while the core is in reset's sequence (a change to the core) or accept it and document that page 1 loses three bytes |
