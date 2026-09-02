
DIR  = $(shell pwd)
SIM_DIR = $(DIR)/sim

src = $(DIR)/rtl/*.v

.phony: all clean compile waveform

all: clean compile waveform

compile:
	@echo "Compiling RTL files..."
	@mkdir -p $(SIM_DIR)
	@iverilog -o $(SIM_DIR)/build $(src) $(DIR)/tb/tb_top.v

clean:
	@echo "Cleaning up..."
	@rm -rf $(SIM_DIR)/build $(SIM_DIR)/waveforms

waveform:
	@echo "Generating waveform..."
	@mkdir -p $(SIM_DIR)/waveforms
	@vvp $(SIM_DIR)/build -lxt2 
# need to fix the vvp command