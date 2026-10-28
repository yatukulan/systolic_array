/*
4x4 INT8 Systolic Array
*/

`timescale 1ns/100ps
`ifndef DISABLE_DEFAULT_NET
`default_nettype none
`endif

// This is the processing element (PE) of an output-stationary systolic array
// Every enabled clock it does one multiply-accumulate (MAC):
//     Accumulator <= Accumulator + A_in * B_in
// and passes its inputs to its neighbours one clock later:
//     A_out (to the PE on the right) <= A_in
//     B_out (to the PE below)        <= B_in
// A_in and B_in are signed INT8, the accumulator is signed INT32.
// The worst case for a 4x4 multiply is 4 * (-128 * -128) = 65,536,
// so 32 bits can never overflow.
module PE (
	input logic Clock,
	input logic Resetn,
	input logic Clear,                // clears the accumulator and the forwarded values
	input logic Enable,               // advances one MAC step
	input logic [7:0] A_in,
	input logic [7:0] B_in,
	output logic [7:0] A_out,
	output logic [7:0] B_out,
	output logic [31:0] Accumulator
);

logic [15:0] product;
logic [31:0] product_extended;

// signed 8 x 8 multiply, then sign-extend the 16-bit product to 32 bits
assign product = $signed(A_in) * $signed(B_in);
assign product_extended = {{16{product[15]}}, product};

always_ff @ (posedge Clock or negedge Resetn) begin
	if (Resetn == 1'b0) begin
		A_out <= 8'd0;
		B_out <= 8'd0;
		Accumulator <= 32'd0;
	end else begin
		if (Clear == 1'b1) begin
			A_out <= 8'd0;
			B_out <= 8'd0;
			Accumulator <= 32'd0;
		end else if (Enable == 1'b1) begin
			A_out <= A_in;
			B_out <= B_in;
			Accumulator <= Accumulator + product_extended;
		end
	end
end

endmodule
