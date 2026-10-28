
vlog -sv -work my_work +define+DISABLE_DEFAULT_NET $rtl/PE.sv
vlog -sv -work my_work +define+DISABLE_DEFAULT_NET $rtl/systolic_array.sv
vlog -sv -work my_work +define+DISABLE_DEFAULT_NET $rtl/matmul_core.sv
vlog -sv -work my_work +define+DISABLE_DEFAULT_NET $rtl/UART_receiver.sv
vlog -sv -work my_work +define+DISABLE_DEFAULT_NET $rtl/PB_controller.sv
vlog -sv -work my_work +define+DISABLE_DEFAULT_NET $rtl/convert_hex_to_seven_segment.sv
vlog -sv -work my_work +define+DISABLE_DEFAULT_NET $rtl/matmul_uart_top.sv

vlog -sv -work my_work +define+DISABLE_DEFAULT_NET $tb/tb_pe.sv
vlog -sv -work my_work +define+DISABLE_DEFAULT_NET $tb/tb_matmul_core.sv
