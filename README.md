# 4×4 INT8 Systolic Array (SystemVerilog, DE2-115)

A matrix-multiply accelerator, the core block of AI chips, built as a 4×4 grid of INT8 multiply-accumulate cells. It is verified with self-checking, seeded, randomized testbenches at unit, block and system level plus a Python regression flow, then run on a DE2-115 FPGA with a PC sending matrices over UART.

**Read first: [doc/PROJECT_OVERVIEW.md](doc/PROJECT_OVERVIEW.md)** for the purpose, design, verification results and how to run it.

## Quick start

```
cd sim && vsim -do run.do                                   # ModelSim, core bench + waves
python3 scripts/regress.py --sim modelsim --seeds 20       # core regression
python3 scripts/regress.py --sim modelsim --tb top         # UART + board display system bench
python3 scripts/regress.py --sim modelsim --inject-bug     # prove the bench catches bugs
```

`--sim verilator` and `--sim iverilog` work too.

## Project structure and conventions

| Convention | Where |
|---|---|
| `board/ rtl/ sim/ syn/ tb/` layout, `TB` testbench with a `UUT` instance | Repository root |
| `setenv.do` / `compile.do` / `run.do` / `waves.do`, `my_work` library, `+define+DISABLE_DEFAULT_NET` | `sim/` |
| Block-comment file header, `` `ifndef DISABLE_DEFAULT_NET `` guard, tabs | Every RTL and testbench file |
| `define_state.h` holding every FSM's `*_state_type` enum | `rtl/define_state.h` |
| `resetn = ~SWITCH_I[17]`, asynchronous active-low reset, sized literals | Every `always_ff` |
| `PB_controller` debounced push buttons | `rtl/PB_controller.sv` (KEY0/1/2 pick the C[i][j] shown) |
| `convert_hex_to_seven_segment`, instances `unit0`..`unit7` | `rtl/convert_hex_to_seven_segment.sv` |
| DE2-115 `pinout_*.tcl` and `timing_50_MHz.sdc` | `board/` |
