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

// This module debounces the 4 push buttons
// Each button is sampled once every CLOCKS_PER_SAMPLE clocks (1 kHz) into a
// 10-bit shift register. A button counts as pressed while any of its last
// 10 samples was pressed, so contact bounce cannot cause extra presses.
// PB_pushed[i] is a 1-clock pulse on every clean press of button i.
module PB_controller (
	input logic Clock_50,
	input logic Resetn,
	input logic [3:0] PB_signal,      // raw push buttons, active low
	output logic [3:0] PB_pushed      // 1-clock pulse per press
);

// clock cycles between samples: 50,000 = 1 kHz at 50 MHz (smaller in simulation)
parameter CLOCKS_PER_SAMPLE = 50000;

logic [15:0] sample_count;
logic sample_enable;
logic [3:0] PB_meta;
logic [3:0] PB_sync;
logic [9:0] debounce_shift_reg [3:0];
logic [3:0] PB_status;
logic [3:0] PB_status_buf;

// two-flop synchronizer, inverted so 1 = pressed
always_ff @ (posedge Clock_50 or negedge Resetn) begin
	if (Resetn == 1'b0) begin
		PB_meta <= 4'h0;
		PB_sync <= 4'h0;
	end else begin
		PB_meta <= ~PB_signal;
		PB_sync <= PB_meta;
	end
end

// 1 kHz sample enable (a clock enable, not a divided clock)
always_ff @ (posedge Clock_50 or negedge Resetn) begin
	if (Resetn == 1'b0) begin
		sample_count <= 16'd0;
		sample_enable <= 1'b0;
	end else begin
		if (sample_count == CLOCKS_PER_SAMPLE - 1) begin
			sample_count <= 16'd0;
			sample_enable <= 1'b1;
		end else begin
			sample_count <= sample_count + 16'd1;
			sample_enable <= 1'b0;
		end
	end
end

// shift registers for debouncing
always_ff @ (posedge Clock_50 or negedge Resetn) begin
	if (Resetn == 1'b0) begin
		debounce_shift_reg[0] <= 10'd0;
		debounce_shift_reg[1] <= 10'd0;
		debounce_shift_reg[2] <= 10'd0;
		debounce_shift_reg[3] <= 10'd0;
	end else begin
		if (sample_enable == 1'b1) begin
			debounce_shift_reg[0] <= {debounce_shift_reg[0][8:0], PB_sync[0]};
			debounce_shift_reg[1] <= {debounce_shift_reg[1][8:0], PB_sync[1]};
			debounce_shift_reg[2] <= {debounce_shift_reg[2][8:0], PB_sync[2]};
			debounce_shift_reg[3] <= {debounce_shift_reg[3][8:0], PB_sync[3]};
		end
	end
end

// debounced button levels, and their values one clock earlier for edge detection
always_ff @ (posedge Clock_50 or negedge Resetn) begin
	if (Resetn == 1'b0) begin
		PB_status <= 4'h0;
		PB_status_buf <= 4'h0;
	end else begin
		PB_status <= {|debounce_shift_reg[3], |debounce_shift_reg[2],
				|debounce_shift_reg[1], |debounce_shift_reg[0]};
		PB_status_buf <= PB_status;
	end
end

// a press is the rising edge of the debounced level
assign PB_pushed = PB_status & ~PB_status_buf;

endmodule
