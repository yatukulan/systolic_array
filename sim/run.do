
# set up paths, top-level module, ...
do setenv.do

# compile the source files
do compile.do

# random seed and number of random matrix pairs (change these, or use scripts/regress.py)
set SEED 1
set NUM_RANDOM 500

# specify library for simulation
vsim -t 100ps -L altera_mf_ver -lib my_work $top -voptargs=+acc +nowarn3116 +SEED=$SEED +NUM_RANDOM=$NUM_RANDOM

# Clear previous simulation
restart -f

# add signals to waveform
do waves.do

# run simulation
run -all

# print simulation statistics
simstats
