
# set up paths, top-level module, ...
do setenv.do
set top TB_PE

# compile the source files
do compile.do

# random seed and number of random steps
set SEED 1
set NUM_RANDOM 2000

# specify library for simulation
vsim -t 100ps -L altera_mf_ver -lib my_work $top -voptargs=+acc +nowarn3116 +SEED=$SEED +NUM_RANDOM=$NUM_RANDOM

# Clear previous simulation
restart -f

# activate waveform simulation
view wave

# format signal names in waveform
configure wave -signalnamewidth 1
configure wave -timeline 0
configure wave -timelineunits us

# add signals to waveform
add wave -divider -height 20 {PE inputs}
add wave -bin clock_50
add wave -bin resetn
add wave -bin clear
add wave -bin en
add wave -decimal a_in
add wave -decimal b_in

add wave -divider -height 10 {PE outputs}
add wave -decimal a_out
add wave -decimal b_out
add wave -decimal acc
add wave -decimal m_acc

# run simulation
run -all

# print simulation statistics
simstats
