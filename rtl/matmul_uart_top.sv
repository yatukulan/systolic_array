/*
4x4 INT8 Systolic Array
*/

`timescale 1ns/100ps
`ifndef DISABLE_DEFAULT_NET
`default_nettype none
`endif

// This is the top module (board bring-up skeleton)
// It proves the pinout, reset, push buttons and displays on the board
// before the datapath exists.
//   SWITCH_I[17]       : reset (up = held in reset)
//   PUSH_BUTTON_N_I[0] : increment a counter, [1] decrement, [2] clear
//   HEX3..HEX0         : counter value (hex)
//   HEX7..HEX4         : test pattern 5A44
//   LED_GREEN_O        : counter[8:0] in binary
//   UART_TX_O          : idle high
module matmul_uart_top (
		/////// board clocks                      ////////////
		input logic CLOCK_50_I,                   // 50 MHz clock

		/////// pushbuttons/switches              ////////////
		input logic[3:0] PUSH_BUTTON_N_I,         // pushbuttons
		input logic[17:0] SWITCH_I,               // toggle switches

		/////// 7 segment displays/LEDs           ////////////
		output logic[6:0] SEVEN_SEGMENT_N_O[7:0], // 8 seven segment displays
		output logic[8:0] LED_GREEN_O,            // 9 green LEDs

		/////// UART                              ////////////
		input logic UART_RX_I,                    // UART receive signal
		output logic UART_TX_O                    // UART transmit signal
);

// clock cycles between push button samples: 1 kHz (smaller in simulation)
parameter PB_CLOCKS_PER_SAMPLE = 50000;

logic resetn;

// For push buttons
logic [3:0] PB_pushed;

logic [15:0] counter;

assign resetn = ~SWITCH_I[17];

PB_controller #(
	.CLOCKS_PER_SAMPLE(PB_CLOCKS_PER_SAMPLE)
) PB_unit (
	.Clock_50(CLOCK_50_I),
	.Resetn(resetn),
	.PB_signal(PUSH_BUTTON_N_I),
	.PB_pushed(PB_pushed)
);

// counter stepped by the push buttons
always_ff @ (posedge CLOCK_50_I or negedge resetn) begin
	if (resetn == 1'b0) begin
		counter <= 16'd0;
	end else begin
		if (PB_pushed[2] == 1'b1) counter <= 16'd0;
		else if (PB_pushed[0] == 1'b1) counter <= counter + 16'd1;
		else if (PB_pushed[1] == 1'b1) counter <= counter - 16'd1;
	end
end

convert_hex_to_seven_segment unit0 (
	.hex_value(counter[3:0]),
	.converted_value(SEVEN_SEGMENT_N_O[0])
);

convert_hex_to_seven_segment unit1 (
	.hex_value(counter[7:4]),
	.converted_value(SEVEN_SEGMENT_N_O[1])
);

convert_hex_to_seven_segment unit2 (
	.hex_value(counter[11:8]),
	.converted_value(SEVEN_SEGMENT_N_O[2])
);

convert_hex_to_seven_segment unit3 (
	.hex_value(counter[15:12]),
	.converted_value(SEVEN_SEGMENT_N_O[3])
);

convert_hex_to_seven_segment unit4 (
	.hex_value(4'h4),
	.converted_value(SEVEN_SEGMENT_N_O[4])
);

convert_hex_to_seven_segment unit5 (
	.hex_value(4'h4),
	.converted_value(SEVEN_SEGMENT_N_O[5])
);

convert_hex_to_seven_segment unit6 (
	.hex_value(4'ha),
	.converted_value(SEVEN_SEGMENT_N_O[6])
);

convert_hex_to_seven_segment unit7 (
	.hex_value(4'h5),
	.converted_value(SEVEN_SEGMENT_N_O[7])
);

assign LED_GREEN_O = counter[8:0];
assign UART_TX_O = 1'b1;

endmodule
