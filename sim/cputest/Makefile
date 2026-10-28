# The 65C02 core alone against Klaus Dormann's test suites.
# The suites are GPL-3 and are fetched, not kept in this repo.
KLAUS_URL = https://github.com/Klaus2m5/6502_65C02_functional_tests
KLAUS_REV = 7954e2dbb49c469ea286070bf46cdd71aeb29e4b
KLAUS     = klaus
CORE      = ../../fpga/third_party/verilog-6502
SRC       = tb_cpu.v $(CORE)/cpu_65c02.v $(CORE)/ALU.v

all: functional

$(KLAUS)/.fetched:
	rm -rf $(KLAUS)
	git clone -q $(KLAUS_URL) $(KLAUS)
	git -C $(KLAUS) checkout -q $(KLAUS_REV)
	touch $@

tb_cpu.vvp: $(SRC)
	iverilog -g2005 -o $@ $(SRC)

functional.hex: $(KLAUS)/.fetched
	python3 bin2memh.py $(KLAUS)/bin_files/6502_functional_test.bin $@

# The NMOS functional test (documented opcodes); passes when it loops at 3469.
functional: tb_cpu.vvp functional.hex
	vvp -n tb_cpu.vvp +image=functional.hex +pass=3469 | grep -E 'PASS|FAIL'

clean:
	rm -f tb_cpu.vvp *.hex

.PHONY: all functional clean
