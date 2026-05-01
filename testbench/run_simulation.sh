#!/bin/bash
# =============================================================================
# Croc SoC Testbench Execution and Simulation Script
# =============================================================================
# This script automates the Verilator compilation and execution flow for
# the Croc SoC functional verification testbench. Performs syntax validation,
# RTL compilation, and simulation with waveform capture.
#
# Execution Environment: IIC-OSIC-TOOLS Docker container
# =============================================================================

set -e

# =============================================================================
# Directory Configuration
# =============================================================================
DESIGN_ROOT="/foss/designs"
BENCH_DIR="${DESIGN_ROOT}/testbench"
OUTPUT_DIR="${DESIGN_ROOT}/results/simulation"

# =============================================================================
# Display Startup Banner
# =============================================================================
printf "\n"
printf "=================================================================\n"
printf "        Croc SoC Simulation and Verification Harness\n"
printf "=================================================================\n"
printf "\n"

cd "$DESIGN_ROOT"

# =============================================================================
# Phase 1: Generate Synthesis File List via Bender
# =============================================================================
echo "[PHASE-1] Preparing RTL file manifest using Bender..."
bender script verilator -t verilator > /tmp/croc_flist.f
echo "          File list generated: /tmp/croc_flist.f"

# =============================================================================
# Phase 2: Syntax and Semantic Analysis with Verilator
# =============================================================================
echo ""
echo "[PHASE-2] Performing static analysis on RTL sources..."
verilator --lint-only -sv \
  --timescale 1ns/1ps \
  -Wno-fatal \
  -Wno-WIDTHEXPAND \
  -Wno-WIDTHTRUNC \
  -Wno-WIDTHCONCAT \
  -Wno-ASCRANGE \
  -Wno-UNOPTFLAT \
  -Wno-UNSIGNED \
  -f /tmp/croc_flist.f \
  --top-module croc_soc \
  2>&1 | tee "$OUTPUT_DIR/verilator_analysis.log"

echo "          Analysis complete: $OUTPUT_DIR/verilator_analysis.log"

# =============================================================================
# Phase 3: RTL-to-C++ Compilation and Executable Generation
# =============================================================================
echo ""
echo "[PHASE-3] Compiling RTL and testbench to executable..."
verilator --binary -sv \
  --timescale 1ns/1ps \
  -Wno-fatal \
  -Wno-WIDTHEXPAND \
  -Wno-WIDTHTRUNC \
  -Wno-WIDTHCONCAT \
  -Wno-ASCRANGE \
  -Wno-UNOPTFLAT \
  -Wno-UNSIGNED \
  -f /tmp/croc_flist.f \
  "$BENCH_DIR/croc_tb.sv" \
  --top-module croc_tb \
  --trace \
  -Mdir "$OUTPUT_DIR/obj_dir" \
  2>&1 | tee "$OUTPUT_DIR/verilator_compile.log"

echo "          Compilation complete: $OUTPUT_DIR/verilator_compile.log"

# =============================================================================
# Phase 4: Execute Simulation and Capture Results
# =============================================================================
echo ""
echo "[PHASE-4] Launching simulation executable..."
"$OUTPUT_DIR/obj_dir/Vcroc_tb" 2>&1 | tee "$OUTPUT_DIR/sim_output.log"

# =============================================================================
# Display Results Summary
# =============================================================================
echo ""
printf "\n"
printf "=================================================================\n"
printf "                    Simulation Completed\n"
printf "=================================================================\n"
printf "\nOutput artifacts located in: $OUTPUT_DIR\n\n"
printf "  • verilator_analysis.log  – RTL lint and type-checking output\n"
printf "  • verilator_compile.log   – Compilation and linking messages\n"
printf "  • sim_output.log          – Functional test results and metrics\n"
printf "  • croc_tb.vcd             – Simulation waveform trace (VCD)\n"
printf "\n"