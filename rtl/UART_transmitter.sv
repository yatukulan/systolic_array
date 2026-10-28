/*
4x4 INT8 Systolic Array
*/

`timescale 1ns/100ps
`ifndef DISABLE_DEFAULT_NET
`default_nettype none
`endif

`include "define_state.h"

// This is an 8N1 UART transmitter (8 data bits, no parity, 1 stop bit)
// Pulse Start for one clock with TX_data valid; Busy stays high until
// the stop bit has been sent.
module UART_transmitter (
	input logic Clock,
	input logic Resetn,
	input logic Start,                // 1-clock pulse, ignored while busy
	input logic [7:0] TX_data,        // byte to send
	output logic UART_TX_O,           // serial output (idle high)
	output logic Busy
);

// clock cycles per bit = 50 MHz / 115200 baud = 434 (smaller in simulation)
parameter CLOCKS_PER_BIT = 434;

TX_controller_state_type TXC_state;

logic [9:0] clock_count;
logic [2:0] bit_count;
logic [7:0] tx_shift;

assign Busy = (TXC_state != S_TXC_IDLE);

// transmit FSM
always_ff @ (posedge Clock or negedge Resetn) begin
	if (Resetn == 1'b0) begin
		TXC_state <= S_TXC_IDLE;
		UART_TX_O <= 1'b1;
		clock_count <= 10'd0;
		bit_count <= 3'd0;
		tx_shift <= 8'd0;
	end else begin
		case (TXC_state)
		S_TXC_IDLE: begin
			UART_TX_O <= 1'b1;
			if (Start == 1'b1) begin
				// latch the byte and send the start bit
				tx_shift <= TX_data;
				clock_count <= 10'd0;
				UART_TX_O <= 1'b0;
				TXC_state <= S_TXC_START_BIT;
			end
		end
		S_TXC_START_BIT: begin
			if (clock_count == CLOCKS_PER_BIT - 1) begin
				// start bit done, send data bit 0
				clock_count <= 10'd0;
				bit_count <= 3'd0;
				UART_TX_O <= tx_shift[0];
				TXC_state <= S_TXC_DATA_BITS;
			end else clock_count <= clock_count + 10'd1;
		end
		S_TXC_DATA_BITS: begin
			if (clock_count == CLOCKS_PER_BIT - 1) begin
				clock_count <= 10'd0;
				if (bit_count == 3'd7) begin
					// all 8 data bits sent, send the stop bit
					UART_TX_O <= 1'b1;
					TXC_state <= S_TXC_STOP_BIT;
				end else begin
					// send the next data bit, LSB first
					bit_count <= bit_count + 3'd1;
					tx_shift <= {1'b0, tx_shift[7:1]};
					UART_TX_O <= tx_shift[1];
				end
			end else clock_count <= clock_count + 10'd1;
		end
		S_TXC_STOP_BIT: begin
			if (clock_count == CLOCKS_PER_BIT - 1) begin
				clock_count <= 10'd0;
				TXC_state <= S_TXC_IDLE;
			end else clock_count <= clock_count + 10'd1;
		end
		default: TXC_state <= S_TXC_IDLE;
		endcase
	end
end

endmodule
