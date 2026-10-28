# activate waveform simulation

view wave

# format signal names in waveform

configure wave -signalnamewidth 1
configure wave -timeline 0
configure wave -timelineunits us

# add signals to waveform

add wave -divider -height 20 {Control}
add wave -bin clock_50
add wave -bin resetn
add wave -bin start
add wave -bin busy
add wave -bin done
add wave UUT/core_state
add wave -uns UUT/step_count

add wave -divider -height 10 {Skewed edges (watch the diagonal wave enter)}
add wave -hex UUT/a_edge
add wave -hex UUT/b_edge

add wave -divider -height 10 {Accumulators C[0][0], C[0][3], C[3][0], C[3][3]}
add wave -decimal {UUT/array_unit/row[0]/column[0]/PE_unit/Accumulator}
add wave -decimal {UUT/array_unit/row[0]/column[3]/PE_unit/Accumulator}
add wave -decimal {UUT/array_unit/row[3]/column[0]/PE_unit/Accumulator}
add wave -decimal {UUT/array_unit/row[3]/column[3]/PE_unit/Accumulator}
