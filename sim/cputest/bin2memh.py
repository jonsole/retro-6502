#!/usr/bin/env python3
"""Turn a binary image into $readmemh form, one byte per line."""
import sys
data = open(sys.argv[1], 'rb').read()
with open(sys.argv[2], 'w') as f:
    f.write(''.join('%02x\n' % b for b in data))
