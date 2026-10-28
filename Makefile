# All compiles run from the repo root. RTL files do not `include each other;
# every compile gets an explicit file list (the same list Vivado uses), and
# the only include path is rtl/include for the shared NoC headers.
#
# Mesh size and other system knobs live in rtl/include/noc_defs.vh. Any of
# them can be overridden per run, e.g.  make mesh MESH_DEFS="-DNOC_MESH_X=3"

IV        = iverilog -g2012 -Irtl/include
VVP       = vvp -n
BUILD     = sim/build
VCD       = sim/waveforms
# compile quietly; on failure print the compiler log and stop
# $(call compile,<name>,<iverilog args>)
compile   = $(IV) -o $(BUILD)/$(1).out $(2) > $(BUILD)/$(1).clog 2>&1 || (cat $(BUILD)/$(1).clog; exit 1)
# run, show the summary lines, and fail the target if any check failed
# $(call run,<name>,<grep pattern for summary lines>)
run       = $(VVP) $(BUILD)/$(1).out > $(BUILD)/$(1).log 2>&1; grep -E "$(2)" $(BUILD)/$(1).log; ! grep -q "FAIL" $(BUILD)/$(1).log

RTL_ROUTER = rtl/router/noc_router.v rtl/router/link_buffer.v rtl/router/end_buff.v
RTL_NI     = rtl/network_interface/address_decoder.v rtl/network_interface/ni.v
RTL_MESH   = rtl/integrated/mesh/noc_mesh.v rtl/integrated/mesh/mesh_top.v rtl/dma_ddr/gw_ni.v
RTL_CORE   = rtl/core/picorv32.v
RTL_ALL    = $(RTL_ROUTER) $(RTL_NI) $(RTL_MESH) $(RTL_CORE)
RTL_BOARD  = rtl/board/reset_sync.v rtl/board/status_panel.v rtl/board/seven_seg.v \
             rtl/board/nexys4ddr/nexys4ddr_top.v

TB_ROUTER = tb/tb_noc_router.v
TB_LB     = tb/tb_link_buffer.v
TB_ADEC   = tb/tb_address_decoder.v
TB_NI     = tb/tb_ni.v
TB_PANEL  = tb/tb_status_panel.v
TB_BOARD  = tb/tb_board.v
TB_MESH   = rtl/integrated/mesh/tb_mesh_top.v
TB_GW     = tb/tb_gw_ni.v tb/axi_dma_model.v

# the router unit test needs a neighbour on every side of the DUT
ROUTER_DEFS = -DNOC_MESH_X=3 -DNOC_MESH_Y=3
MESH_DEFS   ?=

.PHONY: all test clean sw synth_check cocotb \
        router link_buffer address_decoder ni mesh mesh_faults mesh_3x3 \
        alltoall alltoall_3x3 status_panel board gateway wv_router

# Run the whole regression suite.
test: address_decoder link_buffer router ni mesh mesh_faults mesh_3x3 \
      alltoall alltoall_3x3 status_panel board gateway
	@echo ""
	@echo "=== all suites completed ==="

all: test

$(BUILD):
	@mkdir -p $(BUILD) $(VCD)

# ---- unit suites ----

address_decoder: | $(BUILD)
	@echo "=== address_decoder ==="
	@$(call compile,adec,$(TB_ADEC) rtl/network_interface/address_decoder.v)
	@$(call run,adec,PASS:|FAIL)

link_buffer: | $(BUILD)
	@echo "=== link_buffer ==="
	@$(call compile,lb,$(TB_LB) rtl/router/link_buffer.v)
	@$(call run,lb,FAIL|PASSED|TOTAL)

router: | $(BUILD)
	@echo "=== noc_router (3x3 knobs, DUT at the centre) ==="
	@$(call compile,noc_router,$(ROUTER_DEFS) $(TB_ROUTER) rtl/router/noc_router.v)
	@$(call run,noc_router,FAIL|PASSED|TOTAL)

ni: | $(BUILD)
	@echo "=== network interface ==="
	@$(call compile,ni,$(TB_NI) $(RTL_NI))
	@$(call run,ni,FAIL|PASSED|TOTAL)

# ---- full mesh, real picorv32 cores running baremetal images ----

mesh: sw | $(BUILD)
	@echo "=== mesh, healthy with contention ==="
	@$(call compile,mesh0,$(MESH_DEFS) -Ptb_mesh_top.TEST=0 -s tb_mesh_top $(TB_MESH) $(RTL_ALL))
	@$(call run,mesh0,^mesh|FAIL|PASSED|TOTAL)

mesh_faults: sw | $(BUILD)
	@echo "=== mesh, silent-link fault ==="
	@$(call compile,mesh1,-Ptb_mesh_top.TEST=1 -s tb_mesh_top $(TB_MESH) $(RTL_ALL))
	@$(call run,mesh1,FAIL|PASSED|TOTAL)
	@echo "=== mesh, bit-flip fault ==="
	@$(call compile,mesh2,-Ptb_mesh_top.TEST=2 -s tb_mesh_top $(TB_MESH) $(RTL_ALL))
	@$(call run,mesh2,FAIL|PASSED|TOTAL)

# Same software, same RTL, bigger mesh: only the knobs change.
mesh_3x3: sw | $(BUILD)
	@echo "=== mesh, 3x3 via knob override ==="
	@$(call compile,mesh33,-DNOC_MESH_X=3 -DNOC_MESH_Y=3 -Ptb_mesh_top.TEST=0 -s tb_mesh_top $(TB_MESH) $(RTL_ALL))
	@$(call run,mesh33,^mesh|FAIL|PASSED|TOTAL)

# Every tile tests every other tile at once (alltoall.S).
alltoall: sw | $(BUILD)
	@echo "=== mesh, all-to-all self-check ==="
	@$(call compile,a2a,$(MESH_DEFS) -Ptb_mesh_top.TEST=3 -s tb_mesh_top $(TB_MESH) $(RTL_ALL))
	@$(call run,a2a,^mesh|FAIL|PASSED|TOTAL)

alltoall_3x3: sw | $(BUILD)
	@echo "=== mesh, all-to-all self-check, 3x3 ==="
	@$(call compile,a2a33,-DNOC_MESH_X=3 -DNOC_MESH_Y=3 -Ptb_mesh_top.TEST=3 -s tb_mesh_top $(TB_MESH) $(RTL_ALL))
	@$(call run,a2a33,^mesh|FAIL|PASSED|TOTAL)

# ---- board top: status panel, then the whole Nexys4 DDR top from init files ----

status_panel: | $(BUILD)
	@echo "=== status panel (blink codes, priority, display) ==="
	@$(call compile,panel,$(TB_PANEL) rtl/board/status_panel.v)
	@$(call run,panel,FAIL|PASSED|TOTAL)

board: sw | $(BUILD)
	@echo "=== nexys4ddr_top, programs from tileNN.mem, read back from LEDs ==="
	@$(call compile,board,-s tb_board $(TB_BOARD) $(RTL_ALL) $(RTL_BOARD))
	@$(call run,board,FAIL|PASSED|TOTAL)

# ---- gateway: gw_ni in a 2x2 mesh against a behavioural axi_dma model ----
# (the real axi_dma IP is simulated in Vivado: tb/tb_gw_dma_ip.v)

gateway: sw | $(BUILD)
	@echo "=== gateway (gw_ni + DMA model) ==="
	@$(call compile,gw,-s tb_gw_ni $(TB_GW) $(RTL_ALL))
	@$(call run,gw,PASS:|FAIL)
	@$(call compile,gwa2a,-s tb_gw_alltoall tb/tb_gw_alltoall.v $(RTL_ALL))
	@$(call run,gwa2a,FAIL|PASSED|TOTAL)

# ---- synthesis sanity: no combinational loops, no latches ----

synth_check: | $(BUILD)
	@echo "=== yosys: fabric synthesis check ==="
	@yosys -q -l $(BUILD)/yosys.log -p "read_verilog -Irtl/include $(RTL_ROUTER) rtl/integrated/mesh/noc_mesh.v; synth -top noc_mesh -flatten; check -assert" > /dev/null 2>&1
	@echo "latches inferred: $$(grep -c '^Latch inferred' $(BUILD)/yosys.log)"
	@grep "problems" $(BUILD)/yosys.log | tail -1

# ---- pyuvm / cocotb router testbench ----

cocotb:
	@cd cocotb && $(MAKE) --no-print-directory

# ---- software images ----

SW_PROGS = tile0 spin hammer alltoall
sw: $(SW_PROGS:%=sw/%.mem)

$(SW_PROGS:%=sw/%.mem): $(SW_PROGS:%=sw/%.S) sw/build.sh
	@echo "=== building baremetal images ==="
	@sh sw/build.sh

# ---- waveform ----

wv_router: router
	@gtkwave $(VCD)/noc_router.vcd

clean:
	@rm -rf $(BUILD) $(VCD) sw/*.elf sw/*.bin
	@echo "cleaned"
