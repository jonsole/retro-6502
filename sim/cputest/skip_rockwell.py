#!/usr/bin/env python3
"""Patch the prebuilt 65C02 extended opcodes test to skip its Rockwell/WDC
blocks (BBR, BBS, RMB, SMB), which cpu_65c02 does not have.

The prebuilt image was assembled with rkwl_wdc_op = 1. Each block is
replaced by a JMP to the block's last "lda #test_num / sta test_case", so
the test's sequence check still sees the number it expects. Addresses are
from bin_files/65C02_extended_opcodes_test.lst at the pinned commit.
"""
import sys

# (where the block starts, the expected bytes there, where to jump)
PATCHES = [
    (0x071C, bytes([0xA2, 0x11]), 0x0BFF),   # BBR & BBS; resume at lda #8
    (0x1E69, None,                0x2231),   # RMB & SMB; resume at lda #$12
]

data = bytearray(open(sys.argv[1], 'rb').read())
for at, expect, to in PATCHES:
    if expect is not None and data[at:at + len(expect)] != expect:
        sys.exit('skip_rockwell: unexpected bytes at %04x' % at)
    if data[to:to + 2] != bytes([0xA9, 0x08 if to == 0x0BFF else 0x12]):
        sys.exit('skip_rockwell: no lda #test_num at %04x' % to)
    data[at:at + 3] = bytes([0x4C, to & 0xFF, to >> 8])
open(sys.argv[2], 'wb').write(data)
