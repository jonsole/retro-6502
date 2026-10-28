# retro-6502

A 65C02 computer in the FPGA of a ZX Spectrum Next (KS2 for bring-up, KS3 for the full machine): retro-z80's chipset with a 6502 (clone `jonsole/retro-z80` and `jonsole/retro68k` next to this repo).

- Start with `docs/HANDOFF.md`: state of the project, unfinished work, next step.
- Decisions: `docs/design-plan.md` (decision table in section 1 is binding). Specs: `docs/spec/`. Work: GitHub Issues.
- The user decides through a decision tree: 1–4 multiple-choice questions at a time, recommended option first, then write the answers into the plan and specs.
- Spec style follows retro-z80's and retro68k's specs: plain short sentences, British spelling, tables, a test plan and open points.
- **Hardware first.** Build the KS2 bitstream as soon as a change builds and lints, and have the user try it on the board. Locally run only quick, focused tests; CI runs the full simulation suite.

## Working with retro-z80 and retro68k

All three machines share one chipset. retro-z80 is the 8-bit model for this repo; retro68k is the model for both.

- Take the chipset (RTL, specs, tools) from retro-z80 unchanged unless the 6502 forces a difference; record each difference in the spec's "Comparison with retro-z80".
- Copy RTL only from a committed, tested state, and record it in `fpga/rtl/PROVENANCE.md`.
- When unsure, ask the retro-z80 or retro68k session (ListAgents, SendMessage). Don't guess.
- Never edit the other repos from here; suggest changes to their sessions instead. A chipset change the 6502 needs is made in retro-z80 first, then copied.
