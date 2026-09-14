
DIR  = $(shell pwd)
SIM_DIR = $(DIR)/sim
BUILD_DIR = $(SIM_DIR)/build
VCD_DIR = $(SIM_DIR)/vcd_files
WV_DIR = $(SIM_DIR)/waveforms

src = $(DIR)/rtl/*.v

.phony: all clean compile waveform compile_router compile_lb vvp_router wv_router

all: clean compile waveform

compile:
	@echo "Compiling RTL files..."
	@mkdir -p $(SIM_DIR)
	@iverilog -o $(SIM_DIR)/build/top.out $(DIR)/tb/tb_top.v

compile_router:
	@echo "Compiling NOC Router files..."
	@mkdir -p $(SIM_DIR)
	@iverilog -o $(SIM_DIR)/build/noc_router.out $(DIR)/tb/tb_noc_router.v
	@echo "Done compilation"

# need this vcd file to be in vcd_files folder
vvp_router:
	@echo "VVP router check"
	@mkdir -p $(WV_DIR)
	@vvp $(BUILD_DIR)/noc_router.out
	@echo "Done vvp"


wv_router:
	@echo "Loading waveform"
	@gtkwave $(WV_DIR)/noc_router.vcd

compile_lb:
	@echo "Compiling Link Buffer files..."
	@mkdir -p $(SIM_DIR)
	@iverilog -o $(SIM_DIR)/build/lb.out $(DIR)/tb/tb_link_buffer.v
	@echo "Done compilation"

clean:
	@echo "Cleaning up..."
	@rm -rf $(SIM_DIR)/build $(SIM_DIR)/waveforms

waveform:
	@echo "Generating waveform..."
	@mkdir -p $(WV_DIR)
	@vvp $(BUILD_DIR) -lxt2 
