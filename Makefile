# All compiles run from the repo root with -I. so that every `include in the
# RTL can use a path relative to the root. No absolute paths anywhere.

IV        = iverilog -g2012 -I.
BUILD     = sim/build
VCD       = sim/waveforms

TB_ROUTER = tb/tb_noc_router.v
TB_LB     = tb/tb_link_buffer.v
TB_ADEC   = tb/tb_address_decoder.v
TB_4R     = rtl/integrated/four_router_config/tb_four_router.v

.PHONY: all test clean sw \
        router link_buffer address_decoder four_router \
        all_router vvp_router wv_router compile_router compile_lb waveform

# Run the whole regression suite.
test: address_decoder link_buffer router four_router
	@echo ""
	@echo "=== all suites completed ==="

all: test

$(BUILD):
	@mkdir -p $(BUILD) $(VCD)

# ---- individual suites ----

address_decoder: | $(BUILD)
	@echo "=== address_decoder ==="
	@$(IV) -o $(BUILD)/adec.out $(TB_ADEC)
	@vvp $(BUILD)/adec.out

link_buffer: | $(BUILD)
	@echo "=== link_buffer ==="
	@$(IV) -o $(BUILD)/lb.out $(TB_LB)
	@vvp $(BUILD)/lb.out

router: | $(BUILD)
	@echo "=== noc_router ==="
	@$(IV) -o $(BUILD)/noc_router.out $(TB_ROUTER)
	@vvp $(BUILD)/noc_router.out

# Full 2x2 mesh: 4 picorv32 cores running real rv32i images.
four_router: sw | $(BUILD)
	@echo "=== four_router (baremetal, 4 cores) ==="
	@$(IV) -o $(BUILD)/four_router.out $(TB_4R)
	@vvp $(BUILD)/four_router.out

# ---- software images ----

sw: sw/tile0.hex sw/spin.hex

sw/tile0.hex sw/spin.hex: sw/tile0.S sw/spin.S sw/build.sh
	@echo "=== building baremetal images ==="
	@sh sw/build.sh

# ---- waveform ----

wv_router: router
	@gtkwave $(VCD)/noc_router.vcd

# ---- backwards-compatible aliases for the old target names ----
compile_router: router
compile_lb:     link_buffer
vvp_router:     router
all_router:     router wv_router
waveform:       wv_router

clean:
	@rm -rf $(BUILD) $(VCD) sw/*.elf sw/*.bin sw/*.hex
	@echo "cleaned"
