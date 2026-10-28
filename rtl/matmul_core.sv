/*
4x4 INT8 Systolic Array
*/

`timescale 1ns/100ps
`ifndef DISABLE_DEFAULT_NET
`default_nettype none
`endif

`include "define_state.h"

// This module computes C = A x B with an N x N systolic array
// Drive A_flat and B_flat, pulse Start for one clock, then wait for Done.
//   A_flat[(i*N+k)*8 +: 8]   = A[i][k]   (row-major, signed INT8)
//   B_flat[(k*N+j)*8 +: 8]   = B[k][j]   (row-major, signed INT8)
//   C_flat[(i*N+j)*32 +: 32] = C[i][j]   (valid from Done until the next Start)
//
// Skewed feeding: at feed step t, row r of the array receives A[r][t-r] and
// column r receives B[t-r][r] (zero outside 0..N-1). Each PE delays its
// inputs by one clock, so PE(i,j) sees A[i][k] and B[k][j] with the SAME
// k = t - i - j in the same clock, which is exactly the pair it multiplies.
// The last pair reaches PE(N-1,N-1) at t = 3N-3, so the array runs for
// 3N-2 steps (10 for N = 4).
//
// Latency: Done is high 3N clocks after the clock where Start is high
// (1 load + 1 clear + 3N-2 run steps) = 12 clocks for N = 4.
module matmul_core #(
	parameter N = 4
) (
	input logic Clock,
	input logic Resetn,
	input logic Start,                // 1-clock pulse, ignored while busy
	input logic [N*N*8-1:0] A_flat,
	input logic [N*N*8-1:0] B_flat,
	output logic Busy,
	output logic Done,                // 1-clock pulse when C_flat is valid
	output logic [N*N*32-1:0] C_flat
);

// number of feed steps
parameter NUM_STEPS = 3*N - 2;

core_state_type core_state;

logic [N*N*8-1:0] a_reg;              // operands latched at Start
logic [N*N*8-1:0] b_reg;
logic [7:0] step_count;               // current feed step t
logic clear_array;
logic enable_array;
logic [N*8-1:0] a_edge;               // values entering the left edge
logic [N*8-1:0] b_edge;               // values entering the top edge

// control FSM
always_ff @ (posedge Clock or negedge Resetn) begin
	if (Resetn == 1'b0) begin
		core_state <= S_CORE_IDLE;
		step_count <= 8'd0;
		a_reg <= '0;
		b_reg <= '0;
	end else begin
		case (core_state)
		S_CORE_IDLE: begin
			if (Start == 1'b1) begin
				a_reg <= A_flat;
				b_reg <= B_flat;
				core_state <= S_CORE_CLEAR;
			end
		end
		S_CORE_CLEAR: begin
			// the PEs clear their accumulators during this clock
			step_count <= 8'd0;
			core_state <= S_CORE_RUN;
		end
		S_CORE_RUN: begin
			// one MAC step per clock
			if (step_count == NUM_STEPS - 1) core_state <= S_CORE_DONE;
			else step_count <= step_count + 8'd1;
		end
		S_CORE_DONE: begin
			// the results stay in the PE accumulators until the next Start
			core_state <= S_CORE_IDLE;
		end
		default: core_state <= S_CORE_IDLE;
		endcase
	end
end

assign clear_array = (core_state == S_CORE_CLEAR);
assign enable_array = (core_state == S_CORE_RUN);
assign Busy = (core_state != S_CORE_IDLE);
assign Done = (core_state == S_CORE_DONE);

// skewed edge feeders
// row r gets A[r][t-r] and column r gets B[t-r][r]
// t-r is computed in 8 bits, so it wraps to a large value when t < r;
// one "index < N" compare therefore covers both "not started" and "finished"
genvar r;
generate
	for (r = 0; r < N; r = r + 1) begin: feed
		logic [7:0] a_index;
		logic [7:0] b_index;
		logic a_valid;
		logic b_valid;

		assign a_index = step_count - r;
		assign b_index = step_count - r;

		assign a_valid = (core_state == S_CORE_RUN) && (a_index < N);
		assign b_valid = (core_state == S_CORE_RUN) && (b_index < N);

		assign a_edge[r*8 +: 8] = (a_valid == 1'b1) ? a_reg[(r*N + a_index)*8 +: 8] : 8'd0;
		assign b_edge[r*8 +: 8] = (b_valid == 1'b1) ? b_reg[(b_index*N + r)*8 +: 8] : 8'd0;
	end
endgenerate

// the array
systolic_array #(
	.N(N)
) array_unit (
	.Clock(Clock),
	.Resetn(Resetn),
	.Clear(clear_array),
	.Enable(enable_array),
	.A_edge(a_edge),
	.B_edge(b_edge),
	.C_flat(C_flat)
);

endmodule
