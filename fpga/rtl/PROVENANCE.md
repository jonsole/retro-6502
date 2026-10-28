# Provenance

Files copied from other projects. Copy only from a committed, tested state.

| File here | From | Commit | What was changed |
|-----------|------|--------|------------------|
| `fpga/third_party/verilog-6502/cpu_65c02.v`, `ALU.v`, `README.md` | [hoglet67/verilog-6502](https://github.com/hoglet67/verilog-6502) (Arlet Ottens' 6502 core, 65C02 extensions by David Banks and Ed Spittles; "use in any project, keep this message and the copyright notice") | ef2cc5a | `cpu_65c02.v`: D cleared in BRK3 (BRK, IRQ, NMI, reset), as a 65C02 does; `IMPLEMENT_CORRECT_BCD_FLAGS` defined (65C02 N and Z in decimal mode); both found by `sim/cputest`. For spec 1: a `cen` input gating every clocked block (and the ALU's RDY); no writes in reset's sequence (WE = ~res in BRK0–BRK2); a `DUMMY` output marking reads whose byte is thrown away (ABSX1, INDY2, JMPIX1, BRA1 when the access is repeated; READ). `ALU.v` unchanged |
