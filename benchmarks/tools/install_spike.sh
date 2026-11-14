#!/bin/sh
# install_spike.sh -- builds Spike (the RISC-V reference simulator) and dtc
# (the device-tree compiler Spike calls at start-up) from source, into
# benchmarks/third_party/tools. Nothing is installed system-wide.
#
#   sh benchmarks/tools/install_spike.sh
#
# Needed before run_arch_test.py: Spike produces the reference signatures the
# riscv-arch-test results are compared with. Takes about ten minutes.
# Needs: git, make, a C++17 compiler, bison, flex (Xcode command line tools
# on macOS; build-essential bison flex on Debian/Ubuntu).
set -e
cd "$(dirname "$0")/../third_party"
PREFIX="$(pwd)/tools"
mkdir -p "$PREFIX/bin"
JOBS=$( (sysctl -n hw.ncpu || nproc) 2>/dev/null )

if [ ! -x "$PREFIX/bin/dtc" ]; then
    [ -d dtc ] || git clone --depth 1 https://github.com/dgibson/dtc.git
    make -C dtc -j"$JOBS" NO_PYTHON=1 NO_YAML=1 NO_VALGRIND=1 dtc
    cp dtc/dtc "$PREFIX/bin/"
fi

if [ ! -x "$PREFIX/bin/spike" ]; then
    [ -d riscv-isa-sim ] || git clone --depth 1 https://github.com/riscv-software-src/riscv-isa-sim.git
    git -C riscv-isa-sim submodule update --init --depth 1   # softfloat lives in a submodule
    mkdir -p riscv-isa-sim/build
    cd riscv-isa-sim/build
    PATH="$PREFIX/bin:$PATH" ../configure --prefix="$PREFIX"
    make -j"$JOBS"
    make install
fi
echo "spike and dtc are in $PREFIX/bin"
