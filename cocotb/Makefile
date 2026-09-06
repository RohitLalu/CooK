# cocotb/Makefile -- Makefile-based flow for the router testbench.
# Run with: cd cocotb && make
# Waveform: cd cocotb && make WAVES=1
# Different simulator: cd cocotb && make SIM=verilator (if installed)

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# Router RTL lives under rtl/router/, one level up from this folder.
VERILOG_SOURCES += $(PWD)/../rtl/router/noc_router.v

# Must match the module name in noc_router.v exactly.
TOPLEVEL = noc_router

# The Python file (without .py) containing the @cocotb.test() functions.
MODULE = test_router_pyuvm

# Router parameters -- MUST be overridden here to match what the Python
# testbench assumes, or the simulator silently uses noc_router.v's own
# defaults instead (this bit specifically: DATA_W defaults to 32 in the
# RTL, but the testbench assumes 8 -- mismatch here breaks every data
# comparison while still looking like the ports are wired correctly).
COMPILE_ARGS += -Pnoc_router.DX_W=4 -Pnoc_router.DY_W=4 -Pnoc_router.DATA_W=8

include $(shell cocotb-config --makefiles)/Makefile.sim