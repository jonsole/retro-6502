# The 65C02 core alone against Klaus Dormann's test suites, with cen high
# one clock in CEN (10 as at 10 MHz; CEN=1 for every clock), and garbage on
# DI after every read the core marks DUMMY.
# The suites are GPL-3 and are fetched, not kept in this repo.
KLAUS_URL = https://github.com/Klaus2m5/6502_65C02_functional_tests
KLAUS_REV = 7954e2dbb49c469ea286070bf46cdd71aeb29e4b
KLAUS     = klaus
CORE      = ../../fpga/third_party/verilog-6502
CEN      ?= 10
SRC       = tb_cpu.v $(CORE)/cpu_65c02.v $(CORE)/ALU.v

all: functional extended

$(KLAUS)/.fetched:
	rm -rf $(KLAUS)
	git clone -q $(KLAUS_URL) $(KLAUS)
	git -C $(KLAUS) checkout -q $(KLAUS_REV)
	touch $@

# Verilator: the functional test is 96 million cycles (about 25 s here;
# Icarus did not finish in 15 minutes).
obj/Vtb_cpu: $(SRC)
	verilator --binary -j 4 -Wno-fatal -Wno-lint -Wno-style --top-module tb_cpu -Mdir obj $(SRC) > obj.log 2>&1 || (tail obj.log; false)

functional.hex: $(KLAUS)/.fetched
	python3 bin2memh.py $(KLAUS)/bin_files/6502_functional_test.bin $@

extended.hex: $(KLAUS)/.fetched skip_rockwell.py
	python3 skip_rockwell.py $(KLAUS)/bin_files/65C02_extended_opcodes_test.bin extended.bin
	python3 bin2memh.py extended.bin $@

# The NMOS functional test (documented opcodes); passes when it loops at 3469.
functional: obj/Vtb_cpu functional.hex
	obj/Vtb_cpu +image=functional.hex +pass=3469 +cen=$(CEN) | grep -E 'PASS|FAIL' | tee functional.log
	grep -q PASS functional.log

# The 65C02 extended opcodes test, with its Rockwell/WDC blocks skipped;
# passes when it loops at 24f1.
extended: obj/Vtb_cpu extended.hex
	obj/Vtb_cpu +image=extended.hex +pass=24f1 +cen=$(CEN) | grep -E 'PASS|FAIL' | tee extended.log
	grep -q PASS extended.log

clean:
	rm -rf obj obj.log *.hex *.bin *.log

.PHONY: all functional extended clean
