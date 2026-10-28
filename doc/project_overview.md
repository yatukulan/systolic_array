# 4×4 INT8 Systolic Array — Project Overview

## Purpose

Every modern AI chip, from Google's TPU to AMD's Instinct accelerators, spends most of its time doing one thing: **matrix multiplication**. The hardware block that does it fastest is a **systolic array**, a grid of small multiply-accumulate cells that pass data to their neighbours every clock cycle.

This project is a small but complete version of that block:

- **Designed** in SystemVerilog as a 4×4 array of INT8 processing elements with INT32 accumulators.
- **Verified** the way an industry DV team would: directed and randomized tests, a reference model, a scoreboard, protocol checks, coverage counters, a seeded Python regression, and a deliberately injected bug to prove the testbench catches real errors.
- **Deployed** on the DE2-115 FPGA. A PC sends matrices over UART, the FPGA computes C = A × B, and Python checks every result on real hardware.
- **Consistent coding conventions:** `board/ rtl/ sim/ syn/ tb/` layout, block-comment file headers with a `DISABLE_DEFAULT_NET` guard, tabs, all FSM state types in `define_state.h`, `resetn = ~SWITCH_I[17]` with asynchronous active-low reset, sized literals, `*_unit` instance names, and ModelSim `.do` scripts for every testbench.

## Value

| What it shows | Why it matters for Hardware Design / DV roles |
|---|---|
| RTL design of a real AI-accelerator datapath | The same structure used inside machine-learning chips |
| Exact cycle-level timing (skewed data feeding) | The core skill in RTL design: getting the right data to the right place in the right clock |
| Self-checking testbench with a reference model and scoreboard | The standard verification architecture used in industry |
| Randomized, seeded, reproducible tests | Every failure can be re-run with one command |
| Python regression runner (ModelSim / Verilator / Icarus) | Mirrors the Perl/Python regression flows DV teams run every night |
| Bug injection (`INJECT_BUG`) | Proves the testbench can actually find bugs, not just pass |
| Plain, synthesizable SystemVerilog with timing constraints | Ready for Quartus and an FPGA, not just simulation |
| FPGA bring-up with a PC host script | System-level testing of the integrated hardware and software |

---

## 1. How a systolic array works

The goal is to compute **C = A × B**, where A and B are 4×4 matrices of signed 8-bit integers.

Each processing element (PE) does one thing per clock:

```
acc   <= acc + a_in * b_in     // multiply-accumulate (MAC)
a_out <= a_in                  // pass A to the PE on the right
b_out <= b_in                  // pass B to the PE below
```

There are 16 PEs in a 4×4 grid. **PE(i, j) ends up holding C[i][j]** in its accumulator. This is called *output-stationary*, because results stay in place while the inputs flow past.

```
              B col 0   B col 1   B col 2   B col 3
                 ↓         ↓         ↓         ↓
  A row 0 →  [PE 0,0] → [PE 0,1] → [PE 0,2] → [PE 0,3]
                 ↓         ↓         ↓         ↓
  A row 1 →  [PE 1,0] → [PE 1,1] → [PE 1,2] → [PE 1,3]
                 ↓         ↓         ↓         ↓
  A row 2 →  [PE 2,0] → [PE 2,1] → [PE 2,2] → [PE 2,3]
                 ↓         ↓         ↓         ↓
  A row 3 →  [PE 3,0] → [PE 3,1] → [PE 3,2] → [PE 3,3]
```

### The key trick: skewed inputs

PE(i, j) must multiply **A[i][k] × B[k][j]** for k = 0..3, and both values must arrive in the **same clock**. Every PE delays data by one clock, so a value entering row i reaches column j after j clocks. To line things up, **row i of A is fed i clocks late, and column j of B is fed j clocks late**. At feed step `t`:

- row i receives `A[i][t − i]`
- column j receives `B[t − j][j]`
- zero is fed when the index is outside 0..3

PE(i, j) then sees A and B with the same index `k = t − i − j`, which is exactly the pair it needs.

| t | row0 | row1 | row2 | row3 | col0 | col1 | col2 | col3 |
|---|---|---|---|---|---|---|---|---|
| 0 | A00 | 0 | 0 | 0 | B00 | 0 | 0 | 0 |
| 1 | A01 | A10 | 0 | 0 | B10 | B01 | 0 | 0 |
| 2 | A02 | A11 | A20 | 0 | B20 | B11 | B02 | 0 |
| 3 | A03 | A12 | A21 | A30 | B30 | B21 | B12 | B03 |
| 4 | 0 | A13 | A22 | A31 | 0 | B31 | B22 | B13 |
| 5 | 0 | 0 | A23 | A32 | 0 | 0 | B32 | B23 |
| 6 | 0 | 0 | 0 | A33 | 0 | 0 | 0 | B33 |
| 7–9 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

The last pair (A33 × B33) reaches PE(3,3) at t = 3N − 3 = 9, so the array runs for **3N − 2 = 10 steps**. The data moves through the grid as a diagonal wavefront, like a heartbeat, which is where the name "systolic" comes from.

### Number formats

- **Inputs:** signed INT8, −128 to 127, the format used for AI inference.
- **Accumulators:** signed INT32. The worst case is 4 × (−128 × −128) = 65,536, so 32 bits can never overflow at this size.

---

## 2. Architecture

```
            PC (Python)                         DE2-115 FPGA
  ┌───────────────────────┐   RS-232   ┌──────────────────────────────────────┐
  │ uart_host.py          │ ─────────► │ UART_receiver → byte packer (32 B)   │
  │  random A, B          │            │              │                       │
  │  reference model      │            │              ▼                       │
  │  compare C            │ ◄───────── │ UART_transmitter ← serializer (64 B) │
  └───────────────────────┘            │              ▲                       │
                                       │       matmul_core                    │
                                       │   ┌──────────────────────────────┐   │
                                       │   │ FSM: IDLE→CLEAR→RUN×10→DONE  │   │
                                       │   │ skewed edge feeders          │   │
                                       │   │ systolic_array (16 × PE)     │   │
                                       │   └──────────────────────────────┘   │
                                       │ PB0/PB1/PB2: next / prev / C[0][0]   │
                                       │ HEX7–4: selected C[i][j] (low 16 b)  │
                                       │ HEX3–2: i, j    HEX1–0: matrix count │
                                       └──────────────────────────────────────┘
```

| Module | Role |
|---|---|
| `rtl/define_state.h` | FSM state types for the whole design: `core_state_type`, `RX_controller_state_type`, `TX_controller_state_type`, `top_state_type` |
| `rtl/PE.sv` | One processing element: signed 8×8 multiply, 32-bit accumulate, forward A right and B down |
| `rtl/systolic_array.sv` | Generates the 4×4 grid and wires neighbours together (parameterized by N) |
| `rtl/matmul_core.sv` | Control FSM (IDLE → CLEAR → RUN → DONE), operand registers, skewed edge feeders, `INJECT_BUG` hook |
| `rtl/UART_receiver.sv` / `UART_transmitter.sv` | 115200-baud 8N1 UART FSMs; the receiver has a 2-flop input synchronizer and mid-bit sampling |
| `rtl/matmul_uart_top.sv` | DE2-115 top level: receives 32 bytes, starts the core, returns 64 bytes, drives HEX/LEDs; SW17 reset |
| `rtl/PB_controller.sv` | Push-button synchronizer, 1 kHz sampling into 10-bit debounce shift registers, one-clock `PB_pushed` pulse per press |
| `rtl/convert_hex_to_seven_segment.sv` | 7-segment decoder |

**Core interface:** drive `a_flat` and `b_flat`, pulse `start` for one clock, and wait for `done`, which is a one-clock pulse. **Latency: 12 clock cycles** from `start` to `done`. That's 1 load + 1 clear + 10 compute, or 240 ns at 50 MHz.

**UART protocol (115200 baud, 8N1):**
- **PC → FPGA:** 32 bytes. A (16 bytes, row-major, signed) followed by B (16 bytes).
- **FPGA → PC:** 64 bytes. C as 16 × INT32, row-major, little-endian.

---

## 3. Verification

### Testbenches

| Testbench | Level | What it does |
|---|---|---|
| `tb/tb_pe.sv` (module `TB_PE`) | Unit | Every signed corner product, worst-case accumulation, enable hold, clear priority, async reset, then 2,000 random steps checked every clock against a register model. |
| `tb/tb_matmul_core.sv` (module `TB`) | Block | 8 directed tests, then N random matrix pairs. Checks all 16 outputs per test against a reference model, plus latency, `done` pulse width, start-while-busy and reset recovery. Reports coverage counters. |
| `tb/tb_top_uart.sv` (module `TB_TOP`) | System | Acts as the PC: drives serial bytes into the UART RX pin, decodes the reply on the TX pin and checks it. Then acts as the user: presses PB0/PB1/PB2 and decodes the 7-segment outputs to check the displayed C[i][j], index and matrix count. |

Both are written in plain procedural SystemVerilog, so they run unchanged in **ModelSim/Questa, Verilator and Icarus Verilog**. Random stimulus comes from a seeded xorshift32 generator, so **the same seed produces the same matrices in every simulator**.

### Test plan

| # | Test | Purpose |
|---|---|---|
| D0 | All zeros | Basic path, accumulator clear |
| D1 | All 127 × 127 | Largest positive products |
| D2 | All −128 × −128 | Largest possible sum (65,536); signed-multiply corner |
| D3 | 127 × −128 | Most negative products; sign handling |
| D4 | Identity × random | C must equal B exactly; catches row/column swaps |
| D5 | Distinct values 1..16 × −(1..16) | Every element is unique, so any skew or index error shows up |
| D6 | `start` pulsed again while busy | Must be ignored; result must match the original operands |
| D7 | Reset in the middle of a run | All state clears; the next run is correct |
| R | 500 random pairs per seed, back-to-back | General correctness; checks that results never leak between runs |
| P | Every test | Latency exactly 12 cycles; `done` high for exactly 1 cycle |
| U | PE unit test | Signed corners, accumulate, enable hold, clear priority, reset, random cycle-by-cycle |
| S | UART system test | Byte packing, serialization, little-endian order, framing (stop bits) |
| B | Board display test | Debounced buttons step through all 16 elements, wrap both ways, reset to C[0][0]; HEX shows the right value |

**Coverage counters** reported at the end of each run: negative, positive and zero results; (−128)×(−128), 127×(−128) and 127×127 operand pairs; and hits on the maximum sum.

### Regression

`scripts/regress.py` compiles once, runs one simulation per seed, parses `TEST PASSED`/`TEST FAILED`, saves a log per seed, and prints the exact command to reproduce the first failure.

```
python3 scripts/regress.py --sim modelsim  --seeds 50
python3 scripts/regress.py --sim verilator --seeds 100 --num 500
python3 scripts/regress.py --sim iverilog  --seeds 10 --inject-bug
python3 scripts/regress.py --sim verilator --tb top --seeds 5
python3 scripts/regress.py --sim iverilog  --tb pe  --seeds 20
```

### Results

These were run during development with Verilator 5.020 and Icarus Verilog 12. Re-run them in ModelSim to confirm.

| Run | Result |
|---|---|
| PE unit regression, Verilator, 100 seeds × 2,061 checks | **100/100 seeds passed**, 0 errors |
| Core regression, Verilator, 100 seeds × 508 tests | **100/100 seeds passed**: 50,800 matrix multiplies, 812,800 outputs checked, 0 mismatches |
| Core regression, Icarus, 10 seeds × 508 tests | 10/10 passed |
| System (UART + board display) regression, Verilator 10 seeds, Icarus 5 seeds | All seeds passed: every byte correct, 0 framing errors, 0 display errors |
| **Bug injection** (row 3 skewed by one clock) | **Failed on 20/20 seeds**. Errors appear in the first directed tests, all in row 3, which pinpoints the bug |
| Verilator `-Wall` lint, all RTL (width and sign-compare style checks off) | Only intentionally unused signals flagged: spare switches/button and the array's right/bottom edge outputs |
| Yosys synthesis of `matmul_core`, `synth_intel -family cycloneiv` | 970 flip-flops (16 PEs × 48 bits plus the operand registers, minus unused edge registers), about 4.6k logic cells with the multipliers built from logic (about 4% of the EP4CE115). Quartus will map the 16 multipliers to the Cyclone IV's embedded multiplier blocks, so real logic usage will be lower. |

Example of the bug being caught:

```
MISMATCH test 1 C[3][0]: expected 64516, got 48387
MISMATCH test 2 C[3][0]: expected 65536, got 49152
```

---

## 4. How to run it

### ModelSim

```
cd sim
vsim -do run_pe.do     # PE unit testbench
vsim -do run.do        # core testbench with waveforms
vsim -do run_top.do    # full UART + board display system testbench
```

Waveform tip: in `waves.do`, watch `a_edge` and `b_edge` to see the diagonal wavefront enter, then watch the accumulators fill.

### Quartus

1. Open `syn/matmul_uart_top.qpf` in Quartus Prime Lite 19.1.
2. Compile, then check **TimeQuest** for setup slack at 50 MHz and the **Fitter report** for logic elements, registers and embedded multipliers.
3. Program the DE2-115 with `syn/output_files/matmul_uart_top.sof`.

### On the board

1. Connect the DE2-115 RS-232 port to the PC through an RS-232-to-USB adapter.
2. Flip **SW17** up and back down to reset.
3. Run:
   ```
   pip install pyserial
   python3 scripts/uart_host.py --port COM3 --count 1000 --seed 1
   ```
4. HEX1–0 count the matrices processed. Press **KEY0** (next), **KEY1** (previous) or **KEY2** (back to C[0][0]) to pick an element: HEX3–2 show its row and column, HEX7–4 show its low 16 bits in hex.

To check the host script without a board: `python3 scripts/uart_host.py --selftest`.

---

## 5. File structure

```
systolic-array-4x4/
├── rtl/        define_state.h, PE.sv, systolic_array.sv, matmul_core.sv,
│               UART_receiver.sv, UART_transmitter.sv, PB_controller.sv,
│               convert_hex_to_seven_segment.sv, matmul_uart_top.sv
├── tb/         tb_pe.sv, tb_matmul_core.sv, tb_top_uart.sv
├── sim/        setenv.do, compile.do, run_pe.do, run.do, run_top.do, waves.do
├── syn/        matmul_uart_top.qpf / .qsf
├── board/      DE2-115 pinout scripts (clock, keys, switches, LEDs, HEX, UART), timing_50_MHz.sdc
├── scripts/    regress.py, uart_host.py
└── doc/        PROJECT_OVERVIEW.md (this file)
```

---

## 6. Ideas to extend

- **Parameterize the size:** the RTL is already parameterized by N. Try an 8×8 array and compare Quartus resources and Fmax.
- **SystemVerilog assertions (SVA):** add assertions such as "`done` is never high while `busy` is low", if your simulator license supports them.
- **Tiling:** multiply larger matrices by streaming 4×4 tiles through the array.
- **Throughput:** overlap the next load with the current run to remove idle cycles.