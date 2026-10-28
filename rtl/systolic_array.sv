/*
4x4 INT8 Systolic Array
*/

`timescale 1ns/100ps
`ifndef DISABLE_DEFAULT_NET
`default_nettype none
`endif

// This is an N x N grid of PEs (output-stationary)
// Matrix A enters on the left edge (one value per row per clock) and moves right.
// Matrix B enters on the top edge (one value per column per clock) and moves down.
// PE(i,j) keeps C[i][j] in its accumulator.
//   A_edge[i*8 +: 8]         = value entering row i this clock
//   B_edge[j*8 +: 8]         = value entering column j this clock
//   C_flat[(i*N+j)*32 +: 32] = C[i][j]
module systolic_array #(
	parameter N = 4
) (
	input logic Clock,
	input logic Resetn,
	input logic Clear,
	input logic Enable,
	input logic [N*8-1:0] A_edge,
	input logic [N*8-1:0] B_edge,
	output logic [N*N*32-1:0] C_flat
);

// horizontal links: a_link[(i*(N+1)+j)*8 +: 8] is the value entering PE(i,j)
// column N of each row is the output of the last PE (not used)
logic [N*(N+1)*8-1:0] a_link;

// vertical links: b_link[(i*N+j)*8 +: 8] is the value entering PE(i,j)
// row N is the output of the bottom PEs (not used)
logic [(N+1)*N*8-1:0] b_link;

genvar i, j;
generate
	// connect the array edges
	for (i = 0; i < N; i = i + 1) begin: left_edge
		assign a_link[(i*(N+1))*8 +: 8] = A_edge[i*8 +: 8];
	end
	for (j = 0; j < N; j = j + 1) begin: top_edge
		assign b_link[j*8 +: 8] = B_edge[j*8 +: 8];
	end

	// the PE grid
	for (i = 0; i < N; i = i + 1) begin: row
		for (j = 0; j < N; j = j + 1) begin: column
			PE PE_unit (
				.Clock(Clock),
				.Resetn(Resetn),
				.Clear(Clear),
				.Enable(Enable),
				.A_in(a_link[(i*(N+1)+j)*8 +: 8]),
				.B_in(b_link[(i*N+j)*8 +: 8]),
				.A_out(a_link[(i*(N+1)+j+1)*8 +: 8]),
				.B_out(b_link[((i+1)*N+j)*8 +: 8]),
				.Accumulator(C_flat[(i*N+j)*32 +: 32])
			);
		end
	end
endgenerate

endmodule
