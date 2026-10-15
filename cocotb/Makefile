# cocotb/Makefile -- Makefile-based flow for the router testbench.
# Run with: cd cocotb && make      (or `make cocotb` from the repo root)
# Waveform: cd cocotb && make WAVES=1
# Different simulator: cd cocotb && make SIM=verilator (if installed)

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# Router RTL lives under rtl/router/, one level up from this folder.
VERILOG_SOURCES += $(CURDIR)/../rtl/router/noc_router.v

# Must match the module name in noc_router.v exactly.
TOPLEVEL = noc_router

# The Python file (without .py) containing the @cocotb.test() functions.
MODULE = test_router

# Shared NoC headers, plus the knobs the Python side assumes. These MUST
# match Layout(...) in test_router.py: 3x3 mesh, DUT at the centre (1,1) so
# all four neighbours exist. test_router.py asserts the flit width matches.
COMPILE_ARGS += -I$(CURDIR)/../rtl/include -DNOC_MESH_X=3 -DNOC_MESH_Y=3
COMPILE_ARGS += -Pnoc_router.MY_X=1 -Pnoc_router.MY_Y=1

include $(shell cocotb-config --makefiles)/Makefile.sim
