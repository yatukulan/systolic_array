/*
4x4 INT8 Systolic Array
Yatukulan Vivekanandan
Department of Electrical and Computer Engineering
McMaster University
Ontario, Canada
*/

`timescale 1ns/100ps
`ifndef DISABLE_DEFAULT_NET
`default_nettype none
`endif

`include "define_state.h"

// This is an 8N1 UART receiver (8 data bits, no parity, 1 stop bit)
// The serial input is double-flopped to avoid metastability, and each bit
// is sampled in the middle of its bit period.
// RX_data_valid pulses for one clock when a byte with a good stop bit arrives.
module UART_receiver (
	input logic Clock,
	input logic Resetn,
	input logic UART_RX_I,            // serial input (idle high)
	output logic [7:0] RX_data,       // received byte
	output logic RX_data_valid        // 1-clock pulse when RX_data is ready
);

// clock cycles per bit = 50 MHz / 115200 baud = 434 (smaller in simulation)
parameter CLOCKS_PER_BIT = 434;

RX_controller_state_type RXC_state;

logic rx_meta;
logic rx_sync;
logic [9:0] clock_count;
logic [2:0] bit_count;
logic [7:0] rx_shift;

// two-flop synchronizer, since UART_RX_I comes from outside the clock domain
always_ff @ (posedge Clock or negedge Resetn) begin
	if (Resetn == 1'b0) begin
		rx_meta <= 1'b1;
		rx_sync <= 1'b1;
	end else begin
		rx_meta <= UART_RX_I;
		rx_sync <= rx_meta;
	end
end

// receive FSM
always_ff @ (posedge Clock or negedge Resetn) begin
	if (Resetn == 1'b0) begin
		RXC_state <= S_RXC_IDLE;
		clock_count <= 10'd0;
		bit_count <= 3'd0;
		rx_shift <= 8'd0;
		RX_data <= 8'd0;
		RX_data_valid <= 1'b0;
	end else begin
		RX_data_valid <= 1'b0;

		case (RXC_state)
		S_RXC_IDLE: begin
			clock_count <= 10'd0;
			bit_count <= 3'd0;
			// a falling edge on the line is the start bit
			if (rx_sync == 1'b0) RXC_state <= S_RXC_START_BIT;
		end
		S_RXC_START_BIT: begin
			// check the line again in the middle of the start bit to reject glitches
			if (clock_count == CLOCKS_PER_BIT/2 - 1) begin
				clock_count <= 10'd0;
				if (rx_sync == 1'b0) RXC_state <= S_RXC_DATA_BITS;
				else RXC_state <= S_RXC_IDLE;
			end else clock_count <= clock_count + 10'd1;
		end
		S_RXC_DATA_BITS: begin
			// sample the 8 data bits in the middle of each bit, LSB first
			if (clock_count == CLOCKS_PER_BIT - 1) begin
				clock_count <= 10'd0;
				rx_shift <= {rx_sync, rx_shift[7:1]};
				if (bit_count == 3'd7) RXC_state <= S_RXC_STOP_BIT;
				else bit_count <= bit_count + 3'd1;
			end else clock_count <= clock_count + 10'd1;
		end
		S_RXC_STOP_BIT: begin
			// keep the byte only if the stop bit is high
			if (clock_count == CLOCKS_PER_BIT - 1) begin
				clock_count <= 10'd0;
				RXC_state <= S_RXC_IDLE;
				if (rx_sync == 1'b1) begin
					RX_data <= rx_shift;
					RX_data_valid <= 1'b1;
				end
			end else clock_count <= clock_count + 10'd1;
		end
		default: RXC_state <= S_RXC_IDLE;
		endcase
	end
end

endmodule
