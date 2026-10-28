# retro-6502 handoff

Where the project stands and how to carry on. Started on 27 October 2026.

## 1. The project

retro-6502 is retro-z80's machine with a 65C02 in place of the Z80: the same chipset, memory system and board. retro-z80 decided to give it its own repo (retro-z80 design plan, branch 8).

- **Repo:** `jonsole/retro-6502`.
- **Models:** `jonsole/retro-z80` (the chipset, specs, tools and RTL to copy) and `jonsole/retro68k`. Clone both next to this repo.
- **Phase:** 0 (planning). Nothing is built.

## 2. Decided so far

See the design plan, section 1: its own repo, started now, a 65C02 (hoglet67's `cpu_65c02.v`, Arlet Ottens' 6502 with 65C02 extensions), the interrupt controller answering the vector fetch (the bus interface tells an IRQ response from BRK), the register window at `$FE00`–`$FEFF`, RAM in windows 0–6 and ROM in 7 at reset, ca65, retro-z80's memory timing with the 65C02 at 10 MHz, never waiting (a cycle every n slots: 10 MHz down to 1 MHz), no block RAM zero page, the `$FE00` page as the system block, BBC BASIC (licence to find, Q5), retro-z80's monitor and debug link, retro-z80's chipset unchanged.

## 3. Next step

Branches 1–6 are decided (branch 6 replaces branch 5). The core passes Klaus Dormann's functional and 65C02 tests (`make -C sim/cputest`, needs Verilator; about a minute). Next: spec 1 (bus interface), written from retro-z80's spec 1: the slot-locked 10 MHz cycle, the `$FE00` page, the vector fetch.
