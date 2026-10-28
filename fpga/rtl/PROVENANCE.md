# Provenance

Files copied from other projects. Copy only from a committed, tested state.

| File here | From | Commit | What was changed |
|-----------|------|--------|------------------|
| `fpga/third_party/verilog-6502/cpu_65c02.v`, `ALU.v`, `README.md` | [hoglet67/verilog-6502](https://github.com/hoglet67/verilog-6502) (Arlet Ottens' 6502 core, 65C02 extensions by David Banks and Ed Spittles; "use in any project, keep this message and the copyright notice") | ef2cc5a | `cpu_65c02.v`: D cleared in BRK3 (BRK, IRQ, NMI, reset), as a 65C02 does; `IMPLEMENT_CORRECT_BCD_FLAGS` defined (65C02 N and Z in decimal mode). Both found by `sim/cputest` |
