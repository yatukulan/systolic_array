/*
4x4 INT8 Systolic Array
*/

`timescale 1ns/100ps
`ifndef DISABLE_DEFAULT_NET
`default_nettype none
`endif

`include "define_state.h"

// This is the top module
// It receives matrices A and B over the UART, computes C = A x B on the
// 4x4 systolic array, and sends C back over the UART.
//   PC -> FPGA : 32 bytes = A (16 bytes, row-major, signed INT8)
//                         + B (16 bytes, row-major, signed INT8)
//   FPGA -> PC : 64 bytes = C (16 x INT32, row-major, little-endian)
// Board I/O:
//   SWITCH_I[17]       : reset (up = held in reset)
//   PUSH_BUTTON_N_I[0] : show the next element of C (C[0][0] -> C[0][1] -> ... -> C[3][3])
//   PUSH_BUTTON_N_I[1] : show the previous element of C
//   PUSH_BUTTON_N_I[2] : go back to C[0][0]
//   HEX7..HEX4         : low 16 bits of the selected C[i][j] (hex)
//   HEX3, HEX2         : row i, column j of the selected element
//   HEX1, HEX0         : matrices computed since reset (hex)
//   LED_GREEN_O[0]     : waiting for bytes, [1] array busy, [2] transmitting
//   LED_GREEN_O[8:3]   : bytes received so far (0..31)
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

// clock cycles per UART bit: 50 MHz / 115200 baud = 434 (smaller in simulation)
parameter UART_CLOCKS_PER_BIT = 434;

// clock cycles between push button samples: 1 kHz (smaller in simulation)
parameter PB_CLOCKS_PER_SAMPLE = 50000;

logic resetn;

top_state_type top_state;

// For push buttons
logic [3:0] PB_pushed;

// For UART
logic [7:0] UART_rx_data;
logic UART_rx_data_valid;
logic UART_tx_start;
logic [7:0] UART_tx_data;
logic UART_tx_busy;

// For the matrix multiply core
logic [127:0] A_flat;                 // 16 x INT8, row-major
logic [127:0] B_flat;
logic [511:0] C_flat;                 // 16 x INT32, row-major
logic [511:0] C_reg;                  // last result, held for the UART and HEX
logic core_start;
logic core_busy;
logic core_done;

logic [5:0] rx_byte_count;            // 0..31 bytes received
logic [5:0] tx_byte_index;            // 0..63 bytes sent
logic [7:0] matrix_count;             // matrices computed since reset
logic [3:0] C_index;                  // {row i, column j} of the element on HEX7..HEX4
logic [15:0] C_selected;

assign resetn = ~SWITCH_I[17];

PB_controller #(
	.CLOCKS_PER_SAMPLE(PB_CLOCKS_PER_SAMPLE)
) PB_unit (
	.Clock_50(CLOCK_50_I),
	.Resetn(resetn),
	.PB_signal(PUSH_BUTTON_N_I),
	.PB_pushed(PB_pushed)
);

UART_receiver #(
	.CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT)
) UART_RX (
	.Clock(CLOCK_50_I),
	.Resetn(resetn),
	.UART_RX_I(UART_RX_I),
	.RX_data(UART_rx_data),
	.RX_data_valid(UART_rx_data_valid)
);

UART_transmitter #(
	.CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT)
) UART_TX (
	.Clock(CLOCK_50_I),
	.Resetn(resetn),
	.Start(UART_tx_start),
	.TX_data(UART_tx_data),
	.UART_TX_O(UART_TX_O),
	.Busy(UART_tx_busy)
);

matmul_core #(
	.N(4)
) core_unit (
	.Clock(CLOCK_50_I),
	.Resetn(resetn),
	.Start(core_start),
	.A_flat(A_flat),
	.B_flat(B_flat),
	.Busy(core_busy),
	.Done(core_done),
	.C_flat(C_flat)
);

// top FSM: receive A and B, run the core, send C back
always_ff @ (posedge CLOCK_50_I or negedge resetn) begin
	if (resetn == 1'b0) begin
		top_state <= S_TOP_RECEIVE;
		rx_byte_count <= 6'd0;
		tx_byte_index <= 6'd0;
		matrix_count <= 8'd0;
		A_flat <= 128'd0;
		B_flat <= 128'd0;
		C_reg <= 512'd0;
	end else begin
		case (top_state)
		S_TOP_RECEIVE: begin
			if (UART_rx_data_valid == 1'b1) begin
				// bytes 0..15 fill A, bytes 16..31 fill B (row-major)
				if (rx_byte_count < 6'd16) A_flat[rx_byte_count[3:0]*8 +: 8] <= UART_rx_data;
				else B_flat[rx_byte_count[3:0]*8 +: 8] <= UART_rx_data;

				if (rx_byte_count == 6'd31) begin
					rx_byte_count <= 6'd0;
					top_state <= S_TOP_START;
				end else rx_byte_count <= rx_byte_count + 6'd1;
			end
		end
		S_TOP_START: begin
			// core_start is high in this state
			top_state <= S_TOP_COMPUTE;
		end
		S_TOP_COMPUTE: begin
			if (core_done == 1'b1) begin
				C_reg <= C_flat;
				tx_byte_index <= 6'd0;
				top_state <= S_TOP_TX_SEND;
			end
		end
		S_TOP_TX_SEND: begin
			// UART_tx_start is high in this state
			top_state <= S_TOP_TX_WAIT;
		end
		S_TOP_TX_WAIT: begin
			if (UART_tx_busy == 1'b0) begin
				if (tx_byte_index == 6'd63) begin
					matrix_count <= matrix_count + 8'd1;
					top_state <= S_TOP_RECEIVE;
				end else begin
					tx_byte_index <= tx_byte_index + 6'd1;
					top_state <= S_TOP_TX_SEND;
				end
			end
		end
		default: top_state <= S_TOP_RECEIVE;
		endcase
	end
end

assign core_start = (top_state == S_TOP_START);
assign UART_tx_start = (top_state == S_TOP_TX_SEND);

// byte tx_byte_index of the result: element tx_byte_index/4, byte tx_byte_index%4 (little-endian)
assign UART_tx_data = C_reg[tx_byte_index[5:2]*32 + tx_byte_index[1:0]*8 +: 8];

// push buttons select which element of C is shown
always_ff @ (posedge CLOCK_50_I or negedge resetn) begin
	if (resetn == 1'b0) begin
		C_index <= 4'd0;
	end else begin
		if (PB_pushed[2] == 1'b1) C_index <= 4'd0;
		else if (PB_pushed[0] == 1'b1) C_index <= C_index + 4'd1;     // wraps 15 -> 0
		else if (PB_pushed[1] == 1'b1) C_index <= C_index - 4'd1;     // wraps 0 -> 15
	end
end

assign C_selected = C_reg[C_index*32 +: 16];

convert_hex_to_seven_segment unit0 (
	.hex_value(matrix_count[3:0]),
	.converted_value(SEVEN_SEGMENT_N_O[0])
);

convert_hex_to_seven_segment unit1 (
	.hex_value(matrix_count[7:4]),
	.converted_value(SEVEN_SEGMENT_N_O[1])
);

convert_hex_to_seven_segment unit2 (
	.hex_value({2'b00, C_index[1:0]}),
	.converted_value(SEVEN_SEGMENT_N_O[2])
);

convert_hex_to_seven_segment unit3 (
	.hex_value({2'b00, C_index[3:2]}),
	.converted_value(SEVEN_SEGMENT_N_O[3])
);

convert_hex_to_seven_segment unit4 (
	.hex_value(C_selected[3:0]),
	.converted_value(SEVEN_SEGMENT_N_O[4])
);

convert_hex_to_seven_segment unit5 (
	.hex_value(C_selected[7:4]),
	.converted_value(SEVEN_SEGMENT_N_O[5])
);

convert_hex_to_seven_segment unit6 (
	.hex_value(C_selected[11:8]),
	.converted_value(SEVEN_SEGMENT_N_O[6])
);

convert_hex_to_seven_segment unit7 (
	.hex_value(C_selected[15:12]),
	.converted_value(SEVEN_SEGMENT_N_O[7])
);

assign LED_GREEN_O = {rx_byte_count, (top_state == S_TOP_TX_SEND) || (top_state == S_TOP_TX_WAIT),
		core_busy, (top_state == S_TOP_RECEIVE)};

endmodule
