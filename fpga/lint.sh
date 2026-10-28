#!/bin/sh
# Lint the RTL with Verilator, as retro-z80 and retro68k do. A value cut
# short to fit where it goes (WIDTHTRUNC) is an error; widening is allowed.
# Style warnings are left out; other warnings are shown but do not fail.
# The third-party 65C02 core is not checked (fpga/lint.vlt). The KS2 builds
# are linted with stand-ins for the Xilinx primitives (fpga/lint_xilinx_stub.v).
set -e
cd "$(dirname "$0")/.."
VERILATOR=${VERILATOR:-verilator}
CORE="fpga/third_party/verilog-6502/cpu_65c02.v fpga/third_party/verilog-6502/ALU.v"
$VERILATOR --lint-only --default-language 1364-2005 -Wall -Wno-style -Wno-fatal -Werror-WIDTHTRUNC \
    -Ifpga/rtl --top-module retro6502 fpga/lint.vlt $CORE fpga/rtl/*.v
# ... and with all three video layers built (the KS2 builds one)
$VERILATOR --lint-only --default-language 1364-2005 -Wall -Wno-style -Wno-fatal -Werror-WIDTHTRUNC \
    -Ifpga/rtl --top-module retro6502 -GNLAYERS=3 fpga/lint.vlt $CORE fpga/rtl/*.v
$VERILATOR --lint-only --default-language 1364-2005 -Wall -Wno-style -Wno-fatal -Werror-WIDTHTRUNC \
    --top-module top_ks2_pattern fpga/ks2/top_ks2_pattern.v fpga/rtl/tmds_encoder.v \
    fpga/rtl/platform/artix7/ks2_clocks.v fpga/rtl/platform/artix7/hdmi_out.v fpga/lint_xilinx_stub.v
$VERILATOR --lint-only --default-language 1364-2005 -Wall -Wno-style -Wno-fatal -Werror-WIDTHTRUNC \
    -Ifpga/rtl --top-module top_ks2 fpga/lint.vlt $CORE \
    fpga/rtl/*.v fpga/ks2/top_ks2.v fpga/rtl/platform/artix7/ks2_clocks.v \
    fpga/rtl/platform/artix7/hdmi_out.v fpga/rtl/platform/artix7/oddr.v fpga/lint_xilinx_stub.v
echo "lint: no widths cut short"
