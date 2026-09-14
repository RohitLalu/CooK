"""Runner for the pyuvm router testbench. Run with: python3 run_router.py"""
from cocotb_tools.runner import get_runner
import os

if __name__ == "__main__":
    sim = "icarus"
    proj_dir = os.path.dirname(os.path.abspath(__file__))

    runner = get_runner(sim)
    runner.build(
        verilog_sources=[os.path.join(proj_dir, "..", "rtl", "router", "noc_router.v")],
        hdl_toplevel="noc_router",
        parameters={"DX_W": 4, "DY_W": 4, "DATA_W": 8},
        build_dir=os.path.join(proj_dir, "sim_build_router"),
        always=True,
    )
    runner.test(
        test_module="test_router",
        hdl_toplevel="noc_router",
        test_dir=proj_dir,
        build_dir=os.path.join(proj_dir, "sim_build_router"),
    )