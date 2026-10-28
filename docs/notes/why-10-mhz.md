# Why a 6502 runs from SRAM at 10 MHz, not 20

A note on the speed limit behind design plan branch 5. The Z80 in retro-z80 runs at 20 MHz and never waits for memory. A 6502 on the same memory system can only do that at 10 MHz. This note shows why, with the timing taken from retro-z80's spec 1 (bus interface, section 5) and spec 2 (memory, sections 3 and 8).

## 1. Summary

- A read on the shared memory system takes **8 to 13 clocks** (80–130 ns) from a stable address to the byte at the CPU.
- A 6502 often needs the byte it has just read to form its **next** address. So one access must finish before the next can start.
- At 20 MHz a 6502 cycle is **5 clocks**. That is shorter than any read, so the CPU would have to wait.
- At 10 MHz a cycle is **10 clocks**, one slot. A read fits, with about 2 clocks to spare.
- The Z80 fits at 20 MHz because it allows **2 T-states** (10 clocks at 20 MHz) from address to data, and its accesses are at least 3 T-states apart.

## 2. The memory system

retro-z80's memory timing comes from retro68k (design plan branch 11):

| Item | Value |
|------|-------|
| System clock | 100 MHz (10 ns a clock) |
| Memory cycle | 20 ns, one SRAM access |
| Slot | 100 ns, 5 memory cycles, clock edges 0–9 |
| CPU's cycles | Cycle 0 (issued at slot edge 0) and cycle 2 (slot edge 4) |
| Display's cycles | Cycles 1 and 3 |
| Others | Cycle 4: audio, copper, DMA engine, and cycles left unused |

The display needs its cycles at fixed times, so the CPU cannot have a memory cycle whenever it likes. It gets two fixed places in each slot, 40 and 60 ns apart.

## 3. Where the clocks go

A CPU read passes through these steps (retro-z80 spec 1, sections 5.2 and 5.3):

| Step | Clocks | What happens |
|------|--------|--------------|
| Decode and MMU | 3 | The bus interface sees the address, looks up the window's page in the MMU, and loads the request. The request must stand in the clock before its cycle is issued |
| Wait for the CPU's cycle | 0–5 | The next cycle 0 or 2 that is at least 4 clocks after the address |
| SRAM cycle | 4 | The address is on the pins 10–30 ns after the issue; the data is caught in the input pads at issue + 3 and the byte (picked by A0) is at the CPU at issue + 4 |

So the time from a stable address to the byte at the CPU depends on where in the slot the address appears:

| Address stable at slot edge | Cycle issued at | Byte at the CPU | Clocks |
|-----------------------------|-----------------|-----------------|--------|
| 0 | 4 (cycle 2) | 8 | 8 |
| 1 | 10 (next slot's cycle 0) | 14 | 13 |
| 2 | 10 | 14 | 12 |
| 3 | 10 | 14 | 11 |
| 4 | 10 | 14 | 10 |
| 5 | 10 | 14 | 9 |
| 6 | 10 | 14 | 8 |
| 7 | 14 (next slot's cycle 2) | 18 | 11 |
| 8 | 14 | 18 | 10 |
| 9 | 14 | 18 | 9 |

The best case is **8 clocks**, the worst **13**. Even with no MMU and no slots, the SRAM's round trip through the FPGA's pad registers is 4 clocks, and some decoding has to come before it.

## 4. What the 6502 needs

The 6502 makes a memory access on **every** clock cycle. The core (`cpu_65c02.v`) puts out an address in cycle n and uses the byte in cycle n + 1, as if the memory were a synchronous block RAM.

The trouble is that in many cycles the address depends on the byte just read:

| Instruction | Cycles | Address that depends on the last byte |
|-------------|--------|---------------------------------------|
| `JMP $1234` | Fetch opcode, low byte, high byte; then the opcode at `$1234` | The next opcode's address needs the high byte just read |
| `LDA $1234` | Opcode, low, high, data | The data address needs the high byte |
| `LDA ($80),Y` | Opcode, pointer address, pointer low, pointer high, data | Each step needs the byte before it |
| `RTS` | Opcode, …, return low, return high, next opcode | The next opcode needs the return address just pulled |
| Every taken branch | Opcode, offset, next opcode | The new PC needs the offset |

The core shows this directly: its address is `{ DIMUX, ADD }` in the absolute modes and `{ ZEROPAGE, DIMUX }` in the indirect ones, where DIMUX is the byte arriving now.

So the reads form a chain: **byte arrives, next address forms, next read, next byte arrives**. Pipelining cannot help, because the next address is not known until the byte is in. Each link of the chain must fit inside one CPU cycle.

## 5. 20 MHz: does not fit

At 20 MHz a cycle is 5 clocks. The chain needs at least 8 clocks a link (section 3), often more:

| Time (clocks) | What happens |
|---------------|--------------|
| 0 | The high byte of `JMP $1234` arrives; the address `$1234` forms |
| 3 | Request loaded (decode and MMU) |
| 4 or 10 | Cycle 2 or the next cycle 0, depending on where in the slot clock 0 was |
| 5 | **The core wants the opcode at `$1234` now** |
| 8 to 14 | The opcode arrives: 3 to 9 clocks late |

Without a wait, the core would take a wrong byte. With waits (the 6502's RDY), nearly every SRAM access in a chain stretches to 2 or 3 cycles. That makes code in SRAM run about as fast as a 10 MHz 6502 anyway, with uneven timing.

## 6. 10 MHz: fits

At 10 MHz a cycle is 10 clocks, one slot, and the CPU's cycles can be locked to the slots. In steady state:

| Slot edge | What happens |
|-----------|--------------|
| 8 (slot s) | The byte from the last read arrives; the next address forms in the core |
| 1 (slot s + 1) | Request loaded (3 clocks after the address) |
| 4 (slot s + 1) | **Cycle 2** issued |
| 8 (slot s + 1) | The byte arrives |
| 10 (slot s + 1) | The core takes it: **2 clocks to spare** |

Every access, dependent or not, takes exactly one slot, and the CPU never waits. The CPU uses one of its two cycles per slot; the other goes to the free pool, as with the Z80. This is the figure in retro-z80's spec 1, section 4.3.

## 7. Why the Z80 does fit

The Z80 does less per clock and gives memory more time:

| | Z80 at 20 MHz | 6502 at 20 MHz | 6502 at 10 MHz |
|---|---------------|----------------|----------------|
| Clocks from address to data needed | 10 (T1 to end of T2) | 5 | 10 |
| Clocks between accesses | 15 or more (3 T-states) | 5 | 10 |
| Read takes | 8–9 (address at slot edge 0 or 5) | 8–13 | 8 (locked) |
| Waits | None | Most dependent reads | None |

Per clock a 6502 does more work than a Z80: a common rule of thumb is that a 6502 matches a Z80 at about twice its clock. So a 10 MHz 6502 that never waits is roughly level with the 20 MHz Z80 in retro-z80.

## 8. The ways round it

| Way | Speed | Cost | Chosen |
|-----|-------|------|--------|
| 10 MHz, locked to the slots | 10 MHz everywhere, never waits | None | – |
| 20 MHz, every SRAM read waits until its data is in | About 10 MHz from SRAM, 20 MHz from block RAM (the boot ROM) | Uneven timing; RDY in the bus interface | Part of branch 5 |
| **Zero page and stack in block RAM** (`$0000`–`$01FF`), 20 MHz, SRAM accesses wait | 20 MHz for zero page, stack and ROM; about 10 MHz from SRAM | 512 bytes the chipset sees only through the register page; RDY in the bus interface | **Yes, branch 5** |
| Give the CPU all five memory cycles | Shortens the wait for a cycle, but a read still takes at least 7 clocks | The display, copper, sprites and DMA engine lose their bandwidth | No |
| A faster SRAM or a cache | Could reach 20 MHz | Not on the Next's board; a cache is a large design | No |

Zero page and the stack are where 6502 code spends much of its time, as its pointers, variables, and subroutine returns. Putting them in block RAM, which answers in one clock, speeds up the most-used accesses. Code and data in SRAM run at about the 10 MHz speed.

## 9. Open points

| # | Point |
|---|-------|
| N1 | Measure the real mix: run typical code (BASIC, a game loop) in simulation and count SRAM waits, to give the effective speed of branch 5 |
| N2 | Whether the 3 clocks of decode and MMU can be cut to 2, so more addresses catch the earlier CPU cycle (the worst case is 13 clocks when an address just misses one) |
| N3 | Whether instruction fetches from SRAM could be read ahead (the next byte at PC + 1 is often wanted next), as a small prefetch |
