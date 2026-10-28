# Why a 6502 runs from SRAM at 10 MHz, not 20

A note on the speed limit behind design plan branch 5. retro-z80's Z80 runs at 20 MHz and never waits for memory, and so does retro68k's 68000. A 6502 on the same memory system can do that only at 10 MHz. The SRAM is not the reason: it answers in 10 ns. The reasons are how often a 6502 uses memory, how it uses each byte it reads, and the fixed timing grid the memory is shared on.

Timing is from retro-z80's spec 2 (memory, sections 3, 4 and 8) and retro68k's spec 1 (bus interface).

## 1. Summary

- A **6502 uses memory on every clock**. At 20 MHz that is an access every 50 ns. A 68000 or a Z80 at 20 MHz makes one every 150–200 ns.
- Many 6502 cycles **build the next address from the byte just read**. So in those stretches each read has to come back within one CPU cycle: 50 ns at 20 MHz.
- The memory starts a new cycle every 20 ns, but a read takes **40 ns** from the issue to usable data, because of the FPGA's pad flip-flops. With the address forming and the scheduler, the tightest possible loop is exactly 50 ns, with no margin.
- The memory is shared on a **20 ns grid**, with the CPU's turns at fixed places in each 100 ns slot. Those turns are 40 and 60 ns apart; no two cycles of a slot are 50 ns apart. A 20 MHz 6502 needs a steady 50 ns rhythm, which the grid cannot give.
- At **10 MHz** a CPU cycle is one slot, 100 ns. Every read fits, with room to spare, and the CPU never waits.

## 2. The memory system

All three machines share retro68k's memory timing (design plan branch 11 in retro-z80):

| Item | Value |
|------|-------|
| System clock | 100 MHz, 10 ns a clock |
| Memory cycle | 20 ns: a new SRAM access can start every 20 ns |
| Slot | 100 ns: 5 memory cycles, clock edges 0–9 |
| CPU's cycles | Cycle 0 (issued at 0 ns) and cycle 2 (40 ns) |
| Display's cycles | Cycles 1 (20 ns) and 3 (60 ns) |
| Cycle 4 (80 ns) | Audio, copper, DMA engine, and cycles left unused |

The display needs its bytes at fixed times on every line, so ownership is fixed: the CPU always gets cycles 0 and 2, the display always gets 1 and 3.

## 3. One read: 20 ns a cycle, 40 ns to come back

The SRAM controller (retro68k's `sram_ctl.v`) keeps the SRAM busy every 20 ns. But each read takes longer than that to come back, because the address leaves and the data arrives through flip-flops in the FPGA's I/O pads. The pads make the timing clean and the same in every cycle, but each costs a clock:

| Time after the issue | What happens |
|----------------------|--------------|
| 0 ns | Cycle issued: the scheduler picked its owner in the clock before |
| 10 ns | Address out of the output pad flip-flops onto the pins |
| 10–30 ns | The SRAM answers (10 ns part, 10 ns spare for the board and pads) |
| 30 ns | Data caught in the input pad flip-flops |
| 40 ns | Data usable by logic (one more register in the controller) |

So the memory's **throughput** is one access every 20 ns, but its **latency** is 40 ns from the issue, and the request must be in one clock before that.

## 4. What the 6502 needs

The 6502 makes a memory access in every clock cycle. In many cycles the next address is built from the byte just read:

| Instruction | Cycles | Address built from the byte just read |
|-------------|--------|---------------------------------------|
| `JMP $1234` | Opcode, low byte, high byte, then the opcode at `$1234` | The next opcode's address needs the high byte |
| `LDA $1234` | Opcode, low, high, data | The data address needs the high byte |
| `LDA ($80),Y` | Opcode, pointer address, pointer low, pointer high, data | Each step needs the byte before it |
| `RTS` | Opcode, …, return low, return high, next opcode | The next opcode needs the return address |
| A taken branch | Opcode, offset, next opcode | The new PC needs the offset |

The core shows it directly: in the absolute modes its address is `{ DIMUX, ADD }`, in the indirect ones `{ ZEROPAGE, DIMUX }`, where DIMUX is the byte arriving now.

So the reads form a chain: **byte arrives, next address forms, next read issued, next byte arrives**. The next address is not known until the byte is in, so the reads cannot overlap. Each link of the chain has to fit in one CPU cycle. Fast throughput does not help; only latency counts.

## 5. The shortest possible link

Suppose the bus interface is made as tight as it can be: the core takes the byte straight from the input pad flip-flops, and the core's address logic and the MMU look-up fit in one clock.

| Clock | What happens |
|-------|--------------|
| D | The byte is caught in the input pads |
| D to D + 1 | The core forms the next address; the MMU gives the page; the request is loaded at D + 1 |
| D + 2 | The scheduler issues the cycle (the request stood in the clock before) |
| D + 3 to D + 5 | On the SRAM pins |
| D + 5 | The next byte is caught |

A link is **5 clocks, 50 ns**: exactly one 20 MHz cycle, with nothing to spare for slower logic. And it needs a memory cycle issued exactly 5 clocks after the last byte, every time.

## 6. The grid

Memory cycles are issued only on even clock edges (every 20 ns), and the CPU owns two fixed ones per slot:

| CPU's cycles | Issued at | Gaps between them |
|--------------|-----------|-------------------|
| 0 and 2 (as now) | 0 and 40 ns | 40 ns, then 60 ns |
| Any two of the five | 2k × 10 ns apart | 20/80, 40/60, 60/40 or 80/20 ns |

No choice gives 50 and 50 ns. So a 20 MHz 6502 cannot have a memory cycle every 50 ns: whenever a link falls on the 40 ns gap, it is 10 ns short and the CPU must wait. With the real bus interface (retro-z80's needs 3 clocks to decode and look up the MMU) it is short on nearly every link.

Changing which cycles the CPU owns does not help, and giving it more cycles takes them from the display.

## 7. 10 MHz

At 10 MHz a CPU cycle is 100 ns, one slot, and every cycle can be locked to the slots. Each access uses cycle 2 (or cycle 0) of its own slot:

| Slot edge | What happens |
|-----------|--------------|
| 0 | The CPU cycle starts; the address forms (from the last byte, if it depends on one) |
| 3 | Request loaded (even with retro-z80's 3 clocks of decode and MMU) |
| 4 | Cycle 2 issued |
| 8 | The byte is usable |
| 10 | The core takes it and the next cycle starts: 2 clocks to spare |

Every access, dependent or not, takes one slot, and the CPU never waits. It uses one of its two cycles a slot; the other goes to the free pool, as the Z80's spare cycle does. This is the figure in retro-z80's spec 1, section 4.3.

## 8. Compared with retro68k and retro-z80

retro68k's 40 MHz is the clock of its CPU core, fx68k, which needs two clock edges per 68000 clock: the 68000 itself runs at 20 MHz. What lets the 68000 and the Z80 run at 20 MHz with no waits is that they use memory rarely and give each access plenty of time:

| | 68000 at 20 MHz (retro68k) | Z80 at 20 MHz (retro-z80) | 6502 at 10 MHz | 6502 at 20 MHz |
|---|---|---|---|---|
| CPU clocks per memory access | 4 (8 states of 25 ns) | 3 or more T-states | 1 | 1 |
| Time between accesses | 200 ns (2 slots) | 150 ns or more | 100 ns (1 slot) | 50 ns |
| Time from address to data needed | About 150 ns | 100 ns (T1 to the end of T2) | About 100 ns | 50 ns at best |
| Memory cycles used | Cycle 0 of every other slot | At most one of cycles 0 and 2 a slot | One of cycles 0 and 2 a slot | Would need one every 50 ns |
| Waits | 2 when an urgent display fetch takes its cycle (/DTACK) | None, ever | None, ever | On most dependent reads |
| Accesses a second | 5 million, 16 bits each | Up to 6.7 million bytes | 10 million bytes | 20 million bytes |

The clock figures make the 6502 look slow, but it is not. A 6502 makes an access every clock, where the 68000 and the Z80 spread one over 3 or 4. On this shared memory the fair measure is accesses a second, and a 10 MHz 6502 that never waits is already the busiest of the three CPUs. A common rule of thumb is that a 6502 matches a Z80 at about twice its clock, so a 10 MHz 6502 is roughly level with retro-z80's 20 MHz Z80.

## 9. The ways round it

| Way | Speed | Cost | Chosen |
|-----|-------|------|--------|
| 10 MHz, locked to the slots | 10 MHz everywhere, never waits | None | – |
| 20 MHz, an SRAM read waits until its data is in | About 10 MHz from SRAM; 20 MHz from block RAM (the boot ROM) | Uneven timing; RDY in the bus interface | Part of branch 5 |
| **Zero page and stack in block RAM** (`$0000`–`$01FF`), 20 MHz, SRAM accesses wait | 20 MHz for zero page, stack and ROM; about 10 MHz from SRAM | 512 bytes the chipset sees only through the register page; RDY in the bus interface | **Yes, branch 5** |
| A different slot layout for the CPU | Perhaps between 10 and 20 MHz | Changes the chipset shared with retro-z80 and retro68k, and the display's bandwidth | No |
| A faster path to the SRAM (no pad flip-flops) | Saves up to 20 ns a read | Loses the clean, fixed pin timing the whole memory system relies on; still on the 20 ns grid | No |

Block RAM inside the FPGA answers in one clock, so it is not limited by any of this. Zero page and the stack are where 6502 code spends much of its time (pointers, variables, subroutine returns), so putting them in block RAM speeds up the most-used accesses. Code and data in SRAM run at about the 10 MHz speed.

## 10. Open points

| # | Point |
|---|-------|
| N1 | Measure the real mix: run typical code (BASIC, a game loop) in simulation and count SRAM waits, to give the effective speed of branch 5 |
| N2 | How short the 6502's bus interface can make decode and MMU look-up (1 clock, as in section 5, or retro-z80's 3), which sets how long each SRAM wait is |
| N3 | Whether instruction fetches from SRAM could be read ahead (the byte at PC + 1 is often wanted next), using the CPU's spare cycle in each slot |
