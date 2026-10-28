# The boot ROM: boot.bin (the 32 KB image) and boot.hex (bootrom.v's
# $readmemh form). OUT is where they go; KLAUS=1 builds the simulation's
# variant (no self-test; runs the test program in SRAM); FAST=1 a 2-frame
# "second" for the simulation.
CA65   ?= ca65
LD65   ?= ld65
PYTHON ?= python3
OUT    ?= build
ROOT   := ../..
DEFS   := $(if $(KLAUS),-D KLAUS=1,) $(if $(FAST),-D FAST=1,)

all: $(OUT)/boot.hex

$(ROOT)/firmware/include/hw.inc: $(ROOT)/firmware/include/hw.h $(ROOT)/tools/hw2ca65.py
	$(PYTHON) $(ROOT)/tools/hw2ca65.py

$(OUT)/boot.o: boot.s $(ROOT)/firmware/include/hw.inc
	mkdir -p $(OUT)
	$(CA65) --cpu 65C02 -I $(ROOT)/firmware/include $(DEFS) -l $(OUT)/boot.lst -o $@ boot.s

$(OUT)/boot.bin: $(OUT)/boot.o rom.cfg
	$(LD65) -C rom.cfg -m $(OUT)/boot.map -o $@ $(OUT)/boot.o

$(OUT)/boot.hex: $(OUT)/boot.bin
	$(PYTHON) $(ROOT)/tools/bin2hex.py $< $@

clean:
	rm -rf build

.PHONY: all clean
