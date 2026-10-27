# 4×4 INT8 Systolic Array (SystemVerilog, DE2-115)

Work in progress: a 4×4 output-stationary systolic array (INT8 inputs, INT32
accumulators) that computes C = A × B, verified with self-checking
testbenches and run on a DE2-115 FPGA over UART.

```
rtl/     synthesizable SystemVerilog
tb/      testbenches (top-level module TB, as in the labs)
sim/     ModelSim .do scripts (setenv / compile / run)
syn/     Quartus project
board/   DE2-115 pin assignment scripts
scripts/ Python regression and host tools
doc/     design notes
```
