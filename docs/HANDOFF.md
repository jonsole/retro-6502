# retro-6502 handoff

Where the project stands and how to carry on. Started on 27 October 2026.

## 1. The project

retro-6502 is retro-z80's machine with a 65C02 in place of the Z80: the same chipset, memory system and board. retro-z80 decided to give it its own repo (retro-z80 design plan, branch 8).

- **Repo:** `jonsole/retro-6502`.
- **Models:** `jonsole/retro-z80` (the chipset, specs, tools and RTL to copy) and `jonsole/retro68k`. Clone both next to this repo.
- **Phase:** 0 (planning). Nothing is built.

## 2. Decided so far

See the design plan, section 1: its own repo, started now, a 65C02 (hoglet67's `cpu_65c02.v`, Arlet Ottens' 6502 with 65C02 extensions), the interrupt controller answering the vector fetch (the bus interface tells an IRQ response from BRK), the register window at `$FE00`–`$FEFF`, RAM in windows 0–6 and ROM in 7 at reset, ca65, retro-z80's memory timing with the 65C02 at 10 MHz, never waiting (a cycle every n slots: 10 MHz down to 1 MHz), no block RAM zero page, the `$FE00` page as the system block, BBC BASIC (licence to find, Q5), retro-z80's monitor and debug link, retro-z80's chipset unchanged.

## 3. Where things stand

- **Decided:** design plan branches 1–9 (branch 6 replaces branch 5).
- **Core:** `cpu_65c02.v` with the three spec 1 changes (cen, no writes in reset's sequence, DUMMY). It passes Klaus Dormann's functional and 65C02 extended tests with cen every 10 clocks and garbage on every dummy read (`make -C sim/cputest`, needs Verilator; about a minute).
- **Spec 1** (bus interface, `docs/spec/bus-interface.md`), draft: a cycle every n slots on slot edge 0, every SRAM access in cycle 2, dummy reads never made, the `$FE00` page, the IRQ vector table at `$FF00` + VECBASE.
- **Spec 7** (system, `docs/spec/system.md`), draft, as changes to retro-z80's spec 7: reset map, SYSID `0x36`, SYSCFG.CPU = 1, CPUSPEED.
- **Note:** `docs/notes/why-10-mhz.md`.

## 4. Next step

1. Spec 16 (boot ROM and monitor) for the 65C02, from retro-z80's spec 16 and the shared monitor spec.
2. The first KS2 build (hardware first): copy retro-z80's chipset RTL (a committed, tested state, recorded in `fpga/rtl/PROVENANCE.md`), write the bus interface, and a small ca65 boot ROM that runs a self-test and prints over serial and on the boot console.

## 5. From retro-z80 (its session, 28 October 2026)

- Copy the chipset from retro-z80's `main` **at or after 5414e5d**. The PC link changed in 5691edd and 5414e5d to SLIP-style control commands and escapes: `C0 c ~c` is a control command (01 BREAK, 02 RESET, 03 UPLOAD), and data bytes `C0` and `DB` go as `DB DC` and `DB DD` while control is enabled. This fixed a hang where a frame ending in `0x00` was held back; retro68k is adopting it too. `serial.v` and the boot ROM's link code must both follow it.
- Reusable PC tools: `tools/rlink.py` (link, upload, terminal), `tools/rz80_bridge.py` (DAP for VS Code and MCP on port 8780; a stub model with `--model`), `tools/vscode/` (the debugger extension). A 6502 build needs the bridge and stub to know the 65C02's registers (design plan, branch 4).
- The debug unit (retro-z80 spec 18) gives 4 breakpoints and 2 watchpoints in hardware; for retro-6502 it is spec 1's open point B6.
- My retro-z80 changes about the 6502 (the design plan's branch 8 and Q2, the spec 1 note, freeing register page `0x0400`–`0x05FF`) are on retro-z80's branch `claude/festive-goldberg-ui43p7`, not yet on its `main`.
