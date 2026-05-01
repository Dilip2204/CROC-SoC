# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Croc SoC** — a small RISC-V system-on-chip targeting IHP's open-source 130 nm PDK (`ihp-sg13g2`), built from PULP-Platform IPs. Designed for education, so configurability is intentionally limited in favor of readable RTL and scripts. Successfully taped out as MLEM (Nov 2024).

## Toolchain & Environment

All `run_*.sh` scripts source [env.sh](env.sh) at startup, which:
- Exports `CROC_ROOT`, `PROJ_NAME` (default `croc`), `TOP_DESIGN` (default `croc_chip`), `DUT_DESIGN` (default `croc_soc`).
- Auto-discovers the PDK: prefers `technology/` (ETHZ DZ cockpit layout) over `ihp13/pdk/` (the `IHP-Open-PDK` git submodule). When using the submodule it auto-applies `ihp13/patches/0001-Filling-improvements.patch` and creates `ihp13/pdk.patched` as a sentinel — delete that file to force re-patching.
- The official tool environment is the IIC-OSIC-TOOLS docker image, version `2025.12`. Enter via `oseda bash` on ETHZ systems, or `scripts/start_linux.sh` / `scripts/start_vnc.sh` / `scripts/start_vnc.bat` elsewhere. Native installs require Bender, Yosys (+ yosys-slang), OpenROAD, optionally Verilator and Questa.

Run `git submodule update --init --recursive` once after cloning to fetch the PDK.

## Common Commands

All flow scripts live in their tool's directory and accept `--help`. They MUST be run from inside their own directory (they `source ../env.sh`).

| Task | Command |
|------|---------|
| Build all software (RISC-V GCC) | `make -C sw` |
| Clean software | `make -C sw clean` |
| Verilator: regenerate file list | `cd verilator && ./run_verilator.sh --flist` |
| Verilator: build + run a hex | `cd verilator && ./run_verilator.sh --build --run ../sw/bin/helloworld.hex` |
| Questa/Modelsim simulation | `cd vsim && ./run_vsim.sh --build --run ../sw/bin/helloworld.hex` (use `--run-gui` for GUI) |
| Post-synthesis netlist sim | `cd vsim && ./run_vsim.sh --build-netlist --run ...` |
| Yosys synthesis | `cd yosys && ./run_synthesis.sh --flist && ./run_synthesis.sh --synth` |
| OpenROAD P&R (all stages) | `cd openroad && ./run_backend.sh --all` |
| OpenROAD individual stages | `--floorplan`, `--placement`, `--cts`, `--routing`, `--finishing` |
| KLayout DEF→GDS + seal ring | `cd klayout && ./run_finishing.sh --gds --seal` |
| Add metal/active fill | `cd klayout && ./run_finishing.sh --fill` (slow) |
| Xilinx Genesys2 FPGA build | `cd xilinx && ./run_xilinx.sh --all` |
| Lint SV / licenses / Python / C | `scripts/run_checks.sh --sv --license --python --cxx` |

Common flags across `run_*.sh`: `--dry-run|-n`, `--verbose|-v`.

### Running unit tests

Each `sw/test/*.c` produces a hex of the same name. To run them through the Verilator model:

```
cd verilator
./run_verilator.sh --build
.github/scripts/run_tests.sh                                    # all test_*.hex
.github/scripts/run_tests.sh --filter test_uart                 # one test
.github/scripts/run_tests.sh --hexdir ../sw/bin/test --timeout 60
```

A test passes when the simulator log contains `[JTAG] Simulation finished: SUCCESS`; failures emit `FAIL` with a return code.

### Tweaking config without editing files

`.github/scripts/set_croc_config.sh` rewrites a `localparam` in `rtl/croc_pkg.sv` via `sed`, primarily for CI:

```
.github/scripts/set_croc_config.sh iDMAEnable=1   # turn on
.github/scripts/set_croc_config.sh                # `git restore` to defaults
```

The CI's `run_sim_flow.sh` and `run_synth_flow.sh` use this to test default-config and iDMA-enabled in two phases. With iDMA enabled, synthesis runs under `PROJ_NAME=croc_idma` so reports/outputs do not collide.

## Architecture

### Module hierarchy

```
croc_chip            (rtl/croc_chip.sv) — pad ring + PLL hookup; the actual chip-level top
└── croc_soc         (rtl/croc_soc.sv)  — DUT for simulation; instantiates both domains
    ├── croc_domain  (rtl/croc_domain.sv) — CVE2 core, SRAM banks, OBI xbar, peripherals
    └── user_domain  (rtl/user_domain.sv) — student/extension area; OBI sbr+mgr stubs
```

The simulation testbench `tb_croc_soc` (in [rtl/test/](rtl/test/)) drives `croc_soc` via the `croc_vip` (JTAG/UART model). Top-level synthesis target is `croc_chip`; simulation DUT is `croc_soc`.

### Interconnect

- **Main bus**: OBI ([spec](https://github.com/openhwgroup/obi/blob/072d9173c1f2d79471d6f2a10eae59ee387d4c6f/OBI-v1.6.0.pdf)). 32-bit address and data. Manager and subordinate types are spelled out by hand in [rtl/croc_pkg.sv](rtl/croc_pkg.sv) instead of using the `OBI_TYPEDEF_*` macros, for readability.
- The crossbar in `croc_domain` routes 4 managers (Core I, Core D, Debug, User) — plus 2 more if iDMA is enabled — to `Periph`, `User`, the SRAM banks, and an error subordinate. `XbarConnectivity` defaults to fully connected; trim it in `croc_pkg::xbar_connectivity()` to relax routing.
- Peripherals sit behind a separate demux. The address map and `periph_outputs_e` enum live in `croc_pkg.sv`.

### Memory map (defaults)

| Range | Subordinate |
|-------|-------------|
| `0x0000_0000`–`0x0004_0000` | Debug module (JTAG) |
| `0x0200_0000`–`0x0200_4000` | Bootrom |
| `0x0204_0000`–`0x0208_0000` | CLINT |
| `0x0300_0000`–`0x0300_1000` | SoC ctrl/info regs |
| `0x0300_2000`–`0x0300_3000` | UART |
| `0x0300_5000`–`0x0300_6000` | GPIO |
| `0x0300_A000`–`0x0300_B000` | Timer |
| `0x0300_B000`–`0x0300_C000` | iDMA cfg (optional) |
| `0x1000_0000`+ | SRAM banks (size = `NumSramBanks * SramBankNumWords * 4`) |
| `0x2000_0000`–`0x8000_0000` | User domain passthrough |

`BootAddr` defaults to `0x1000_0000` (start of SRAM). New peripherals should occupy whole 4 KB regions and ideally stay compatible with [Cheshire's memory map](https://pulp-platform.github.io/cheshire/um/arch/#memory-map). The current only boot path is **JTAG**.

### SRAM technology wrapping

`tc_sram_impl` is a tech wrapper. The behavioral model in [rtl/tech_cells_generic/tc_sram_impl.sv](rtl/tech_cells_generic/tc_sram_impl.sv) is the simulation default. The IHP130 implementation in [ihp13/tc_sram_impl.sv](ihp13/tc_sram_impl.sv) is selected by Bender target `ihp13`. If a configuration has no implementation, `tc_sram_blackbox` is instantiated so post-synthesis greps catch it.

## Bender (dependency manager)

[Bender.yml](Bender.yml) declares dependencies and source files; [Bender.lock](Bender.lock) pins resolved revisions. **Always retest after `bender update` regenerates the lock — it is equivalent to changing RTL.**

### Targets

Different simulator/tech contexts are selected by Bender targets — file lists pass them with `-t`:

- `rtl` — RTL view (excluded under `netlist_yosys`).
- `ihp13` — pulls in tech-specific cells (`tc_clk.sv`, `tc_sram_impl.sv` from `ihp13/`).
- `verilator`, `vsim`, `simulation` — testbench files.
- `synthesis`, `asic` — synthesis context.
- `netlist_yosys` — replaces RTL with `yosys/out/netlist_debug.v` for gate-level sim.
- `genesys2`, `fpga` — Xilinx FPGA build (excludes `croc_chip.sv` pad ring).

### Vendored IPs

Most of `rtl/<IP>/` is **not hand-written here** — it is checked in via `bender vendor` from upstream PULP repos (see `vendor_package` in [Bender.yml](Bender.yml)). Patches against upstream live in [rtl/.patches/](rtl/.patches/). To update an IP's mapping or apply a local fix:

```
bender vendor init                # re-fetch using updated mapping
git add <local fix>
bender vendor patch               # save staged diff as a patch (prompts for filename/commit message)
```

This requires Bender ≥ 0.28.2. Don't edit `rtl/<vendored IP>/` files directly without round-tripping the change to a patch — `bender vendor init` will overwrite them.

## Software (sw/)

- [sw/Makefile](sw/Makefile) builds every `*.{c,S}` in `sw/` and `sw/test/` into `sw/bin/<name>.{elf,dump,hex}` using `riscv64-unknown-elf-gcc` (override via `RISCV_PREFIX`).
- Targets `rv32i_zicsr` / `ilp32`. Library code is in `sw/lib/{src,inc}`, linker script `sw/link.ld`, startup `sw/crt0.S`.
- Hex format is verilog-readmemh, suitable for `+binary=...` in the Verilator/Questa testbench.

## Style & Linting

- SystemVerilog: Verible with [scripts/verible.rules](scripts/verible.rules) and [scripts/verible.waiver](scripts/verible.waiver). Lint via `scripts/run_checks.sh --sv` (skips `rtl/cve2/`).
- C: `clang-format` 17, config in [.clang-format](.clang-format). Run `scripts/run_checks.sh --cxx`.
- Python: `black`, line length 120, target py38 (see [pyproject.toml](pyproject.toml)).
- License headers: SHL-0.51 for hardware/scripts, Apache-2.0 for software. Verified by [scripts/lint_license.py](scripts/lint_license.py) using [scripts/license_cfg.yml](scripts/license_cfg.yml).

CI workflows: `format.yml` (black + clang-format), `short-flow.yml` (sim + synth on every push), `full-flow.yml` (Yosys + OpenROAD + KLayout, on PRs/main/release).

## Adding your own design

1. Drop sources into `rtl/user_domain/` (or a new `rtl/<your_ip>/`), then add them to [Bender.yml](Bender.yml) under the indicated comments. Module-free files (packages) go to the top "Level 0" block; modules go to the `not(netlist_yosys)` block.
2. Regenerate file lists: `cd yosys && ./run_synthesis.sh --flist` and `cd ../verilator && ./run_verilator.sh --flist`.
3. If you need a new peripheral region, extend `periph_outputs_e` and `PeriphAddrMap` in [rtl/croc_pkg.sv](rtl/croc_pkg.sv).
4. The MLEM tapeout convention is a small user ROM at `0x2000_0000` containing project metadata as a zero-terminated ASCII string — see [the MLEM reference](https://github.com/pulp-platform/croc/blob/mlem-tapeout/rtl/user_domain/user_rom.sv).
