# Single-bus baseline. Run from this directory: make test
# Independent of the NoC build: its own targets and outputs. The files under
# ../rtl that both architectures share are listed in RTL_SHARED and are never
# modified from here.

IV      = iverilog -g2012 -I../rtl/include
VVP     = vvp -n
BUILD   = sim/build
compile = $(IV) -o $(BUILD)/$(1).out $(2) > $(BUILD)/$(1).clog 2>&1 || (cat $(BUILD)/$(1).clog; exit 1)
run     = $(VVP) $(BUILD)/$(1).out > $(BUILD)/$(1).log 2>&1; grep -E "$(2)" $(BUILD)/$(1).log; ! grep -q "FAIL" $(BUILD)/$(1).log

RTL_SHARED = ../rtl/core/picorv32.v
VAXI       = third_party/verilog-axi/axil_interconnect.v third_party/verilog-axi/arbiter.v \
             third_party/verilog-axi/priority_encoder.v
RTL_BUS    = rtl/sb_axil_tile.v rtl/sb_axil_info.v rtl/sb_axil_bus.v rtl/sb_top.v $(VAXI)
RTL_ALL    = $(RTL_BUS) $(RTL_SHARED)
RTL_BOARD  = ../rtl/board/reset_sync.v ../rtl/board/status_panel.v ../rtl/board/seven_seg.v \
             rtl/sb_nexys4ddr_top.v
MODEL      = tb/axi4_mem_model.v

.PHONY: all test clean sw axi system faults board soak synth_check

test: axi system faults board soak
	@echo ""
	@echo "=== single-bus suites completed ==="

all: test

$(BUILD):
	@mkdir -p $(BUILD)

axi: | $(BUILD)
	@echo "=== AXI bus parts (tiles, windows, DDR, decode error, stuck bus, restart) ==="
	@$(call compile,axi,-s tb_sb_axi tb/tb_sb_axi.v $(MODEL) $(RTL_BUS))
	@$(call run,axi,FAIL|PASSED|TOTAL)

# real picorv32 cores: the NoC's own images, then the DDR test
system: sw | $(BUILD)
	@echo "=== bus system, alltoall.S on three cores ==="
	@$(call compile,sys0,-Ptb_sb_top.TEST=0 -s tb_sb_top tb/tb_sb_top.v $(MODEL) $(RTL_ALL))
	@$(call run,sys0,^bus|FAIL|PASSED|TOTAL)
	@echo "=== bus system, ddr.S on three cores (shared DDR, contention) ==="
	@$(call compile,sys1,-Ptb_sb_top.TEST=1 -s tb_sb_top tb/tb_sb_top.v $(MODEL) $(RTL_ALL))
	@$(call run,sys1,^bus|FAIL|PASSED|TOTAL)

faults: sw | $(BUILD)
	@echo "=== bus system, stuck arbiter (M3 baseline) ==="
	@$(call compile,sys2,-Ptb_sb_top.TEST=2 -s tb_sb_top tb/tb_sb_top.v $(MODEL) $(RTL_ALL))
	@$(call run,sys2,^bus|FAIL|PASSED|TOTAL)
	@echo "=== bus system, flipped data wire (M3 baseline) ==="
	@$(call compile,sys3,-Ptb_sb_top.TEST=3 -s tb_sb_top tb/tb_sb_top.v $(MODEL) $(RTL_ALL))
	@$(call run,sys3,^bus|FAIL|PASSED|TOTAL)

board: sw | $(BUILD)
	@echo "=== sb_nexys4ddr_top, programs from init files, read back from LEDs ==="
	@$(call compile,board,-s tb_sb_board tb/tb_sb_board.v $(MODEL) $(RTL_ALL) $(RTL_BOARD))
	@$(call run,board,FAIL|PASSED|TOTAL)
	@echo "=== sb_nexys4ddr_top, fault switch SW = 0x1000 (stuck arbiter) ==="
	@$(call compile,boardf,-Ptb_sb_board.FAULT_SW=16\'h1000 -s tb_sb_board tb/tb_sb_board.v $(MODEL) $(RTL_ALL) $(RTL_BOARD))
	@$(call run,boardf,FAIL|PASSED|TOTAL)

# the NoC's randomised soak test, on the bus (four and nine nodes)
SOAK_RTL = ../tb/tb_soak.v rtl/sb_axil_tile.v rtl/sb_axil_info.v rtl/sb_axil_bus.v $(VAXI)
soak: | $(BUILD)
	@echo "=== soak: random traffic from every node, scoreboard ==="
	@$(call compile,soak,-DSOAK_BUS -Ptb_soak.SEED=1 $(SOAK_RTL))
	@$(call run,soak,^soak|FAIL|PASSED|TOTAL)
	@$(call compile,soak9,-DSOAK_BUS -DNOC_MESH_X=3 -DNOC_MESH_Y=3 -Ptb_soak.SEED=2 $(SOAK_RTL))
	@$(call run,soak9,^soak|FAIL|PASSED|TOTAL)

synth_check: | $(BUILD)
	@echo "=== yosys: AXI tile, memory-node registers and bus, latches and loops ==="
	@yosys -q -l $(BUILD)/yosys.log -p "read_verilog -I../rtl/include rtl/sb_axil_tile.v rtl/sb_axil_info.v rtl/sb_axil_bus.v $(VAXI); hierarchy -check -top sb_axil_bus; synth -flatten -top sb_axil_bus; check -assert; design -reset; read_verilog -I../rtl/include rtl/sb_axil_tile.v; synth -flatten -top sb_axil_tile; check -assert; design -reset; read_verilog -I../rtl/include rtl/sb_axil_info.v; synth -flatten -top sb_axil_info; check -assert" > /dev/null 2>&1 || (tail -5 $(BUILD)/yosys.log; exit 1)
	@echo "latches inferred: $$(grep -c '^Latch inferred' $(BUILD)/yosys.log)"
	@grep "problems" $(BUILD)/yosys.log | tail -3

# ddr.S here; alltoall.mem comes from the NoC's sw/ (prebuilt, shared)
sw: sw/ddr.mem
sw/ddr.mem: sw/ddr.S sw/build.sh
	@sh sw/build.sh

clean:
	@rm -rf $(BUILD) sw/*.elf sw/*.bin
	@echo "cleaned"
