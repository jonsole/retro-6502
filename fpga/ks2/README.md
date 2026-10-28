# Building for the ZX Spectrum Next KS2

Two builds for the KS2 (issue 4, XC7A15T-1CSG324), as retro-z80's:

- **The computer** (`top_ks2.v`): the 65C02 at 10 MHz behind its bus interface (spec 1), the MMU, the scheduler and SRAM controller on the KS2's 2 MB SRAM, the boot ROM, the system registers, USB serial on the accelerator header, the interrupt controller with INTCON.VECTOR, the timers and watchdog, the video unit (one layer built), the copper, sprites, the keyboards and joysticks: retro-z80's chipset, unchanged but for INTCON.VECTOR and the system registers. No beeper (spec 7, section 10).
- **The test pattern** (`top_ks2_pattern.v`): colour bars on HDMI and VGA, unchanged from retro-z80.

```
fpga/ks2/build.sh                    # the computer -> fpga/ks2/build/retro6502_ks2.bit
fpga/ks2/build.sh --program          # build, then load it over JTAG
fpga/ks2/build.sh --program-only     # load the last build
fpga/ks2/build.sh --pattern          # the test pattern
```

**You need:** Vivado 2026.1, as for retro-z80; **cc65** (`ca65` and `ld65`, on the PATH or named by `CA65` and `LD65`), GNU make and Python 3 for the boot ROM. On Windows, from Git Bash or the MSYS2 shell, at the repository root:

```
VIVADO=/c/AMDDesignTools/2026.1/Vivado/bin/vivado.bat bash fpga/ks2/build.sh --program
```

cc65 for Windows: the snapshot zip from cc65's GitHub releases; put its `bin` folder on the PATH, or `CA65=/c/cc65/bin/ca65.exe LD65=/c/cc65/bin/ld65.exe`. Loading over JTAG works as in retro-z80's KS2 README (cable, header, power, then `--program-only`); it changes only the FPGA until the power goes off.

## The computer: what you should see

On HDMI and VGA at 720 × 576, 50 Hz, the whole screen is the background colour (BGCOLOR), which boot ROM 0.1 (`firmware/boot/boot.s`) drives:

| Screen | Meaning |
|--------|---------|
| No signal | The FPGA is not loaded, the clocks are not running, or the 65C02 did not run the ROM's first instructions (they turn the beam on) |
| Blue | Start-up and the power-on self-test of the SRAM (a few ms, so only a flash). **Blue that stays** means the 65C02 stopped there |
| Red | The self-test failed: `selftest FAIL nn` on the serial link (`01` SYSID wrong, `10` data lines, `11` address lines) |
| Green, a flash | The self-test passed |
| **4 s of a rainbow, then 4 s of a blue pulse, and so on** | **The 65C02 runs and takes the VBLANK interrupt at 50 Hz.** The rainbow comes from the vectored handler (INTCON.VECTOR set: the table entry at `$FFD0`), the blue pulse from the plain one (`$FFFE`, reading INTID). The colour steps every 4 frames. Both colours changing means both IRQ modes work |

The reset button restarts it (no self-test then: RESETWHY is BUTTON). With an FT232H fitted (not yet), the serial link shows `retro-6502 boot ROM 0.1  65C02 at 10 MHz`, then a line a second: `second $0001  IRQ vectored`.

In simulation the same ROM, with a 2-frame "second", runs in `make -C sim boot`.
