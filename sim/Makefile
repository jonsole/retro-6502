# The whole machine in Verilator (sim/tb.v), and the lint.
#   make -C sim boot     the boot ROM (its FAST variant) until 6 "seconds",
#                        both IRQ modes seen; about a minute
#   make -C sim klaus    Klaus Dormann's 6502 functional test from SRAM, run
#                        by the boot ROM's KLAUS variant: 96 million cycles,
#                        long (run it when there is a reason)
#   make -C sim ext      the 65C02 extended opcodes test the same way
#   make -C sim lint
ROOT  := ..
RTL   := $(ROOT)/fpga/rtl
CORE  := $(ROOT)/fpga/third_party/verilog-6502
SRC   := tb.v sram_model.v ft232h_model.v $(RTL)/platform/sim/oddr.v \
         $(CORE)/cpu_65c02.v $(CORE)/ALU.v $(filter-out $(RTL)/README.md,$(wildcard $(RTL)/*.v))
BOOT  := $(ROOT)/firmware/boot
KLAUS := $(ROOT)/sim/cputest/klaus

obj/Vtb: $(SRC)
	verilator --binary -j 4 -O3 -Wno-fatal -Wno-lint -Wno-style --timing -I$(RTL) \
	    --top-module tb -Mdir obj $(SRC) > obj.log 2>&1 || (tail -20 obj.log; false)

rom/fast/boot.hex: $(BOOT)/boot.s
	$(MAKE) -s -C $(BOOT) FAST=1 OUT=$(abspath rom/fast)
rom/klaus/boot.hex: $(BOOT)/boot.s
	$(MAKE) -s -C $(BOOT) KLAUS=1 OUT=$(abspath rom/klaus)

$(KLAUS)/.fetched:
	$(MAKE) -C cputest klaus/.fetched
functional.hex: $(KLAUS)/.fetched
	python3 $(ROOT)/tools/bin2hex.py $(KLAUS)/bin_files/6502_functional_test.bin $@ 32768
extended.hex: $(KLAUS)/.fetched
	python3 cputest/skip_rockwell.py $(KLAUS)/bin_files/65C02_extended_opcodes_test.bin extended.bin
	python3 $(ROOT)/tools/bin2hex.py extended.bin $@ 32768

boot: obj/Vtb rom/fast/boot.hex
	obj/Vtb +rom=rom/fast/boot.hex +boot=6 +max=4000000 | tee boot.log | tail -4
	grep -q PASS boot.log

klaus: obj/Vtb rom/klaus/boot.hex functional.hex
	obj/Vtb +rom=rom/klaus/boot.hex +ram=functional.hex +pass=3469 +max=100000000 | tail -4 | tee klaus.log
	grep -q PASS klaus.log

ext: obj/Vtb rom/klaus/boot.hex extended.hex
	obj/Vtb +rom=rom/klaus/boot.hex +ram=extended.hex +pass=24f1 +max=70000000 | tail -4 | tee ext.log
	grep -q PASS ext.log

lint:
	sh $(ROOT)/fpga/lint.sh

clean:
	rm -rf obj obj.log rom *.hex *.bin *.log

.PHONY: boot klaus ext lint clean
