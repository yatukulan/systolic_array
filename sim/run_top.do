
# set up paths, top-level module, ...
do setenv.do
set top TB_TOP

# compile the source files
do compile.do

# random seed and number of random matrices sent over the UART
set SEED 1
set NUM_MATRICES 20

# specify library for simulation
vsim -t 100ps -L altera_mf_ver -lib my_work $top -voptargs=+acc +nowarn3116 +SEED=$SEED +NUM_MATRICES=$NUM_MATRICES

# Clear previous simulation
restart -f

# activate waveform simulation
view wave

# format signal names in waveform
configure wave -signalnamewidth 1
configure wave -timeline 0
configure wave -timelineunits us

# add signals to waveform
add wave -divider -height 20 {UART pins}
add wave -bin uart_rx
add wave -bin uart_tx

add wave -divider -height 10 {Top-level FSM}
add wave UUT/top_state
add wave -uns UUT/rx_byte_count
add wave -uns UUT/tx_byte_index
add wave -uns UUT/matrix_count
add wave -bin UUT/core_start
add wave -bin UUT/core_done

# run simulation
run -all

# print simulation statistics
simstats
