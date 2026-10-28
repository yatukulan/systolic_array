/*
4x4 INT8 Systolic Array
*/

// This is the self-checking unit testbench for one processing element
//
//   * Directed: every signed corner product (-128, -1, 0, 1, 127 squared),
//     accumulate across steps, en = 0 holds all state, clear wins over en,
//     reset clears everything
//   * Random: NUM_RANDOM steps with random a, b, en and clear, checked
//     every clock against a cycle-accurate model of the PE registers
//
// Plusargs:  +SEED=<n>  +NUM_RANDOM=<n>
// Prints "TEST PASSED" or "TEST FAILED" (parsed by scripts/regress.py).

`timescale 1ns/100ps
`ifndef DISABLE_DEFAULT_NET
`default_nettype none
`endif

module TB_PE;

	parameter DW = 8;
	parameter AW = 32;

	logic                 clock_50 = 1'b0;
	logic                 resetn, clear, en;
	logic signed [DW-1:0] a_in, b_in;
	logic signed [DW-1:0] a_out, b_out;
	logic signed [AW-1:0] acc;

	always begin
		#10;
		clock_50 = ~clock_50;
	end

		PE UUT (
		.Clock(clock_50),
		.Resetn(resetn),
		.Clear(clear),
		.Enable(en),
		.A_in(a_in),
		.B_in(b_in),
		.A_out(a_out),
		.B_out(b_out),
		.Accumulator(acc)
	);

	// Model of the PE registers
	int m_acc, m_a, m_b;
	int seed, num_random, checks, errors;
	logic [31:0] rng_state;

	function logic [31:0] rng_next();
		logic [31:0] x;
		x = rng_state;
		x = x ^ (x << 13);
		x = x ^ (x >> 17);
		x = x ^ (x << 5);
		rng_state = x;
		return x;
	endfunction

	// Apply inputs at the negedge, clock them in, update the model, compare
	task step(input int a, input int b, input logic e, input logic c);
		a_in  = a;
		b_in  = b;
		en    = e;
		clear = c;
		@(posedge clock_50);
		if (c) begin
			m_acc = 0; m_a = 0; m_b = 0;
		end else if (e) begin
			m_acc = m_acc + a * b;
			m_a   = a;
			m_b   = b;
		end
		@(negedge clock_50);
		checks++;
		if (acc !== m_acc || a_out !== m_a || b_out !== m_b) begin
			errors++;
			if (errors <= 10)
				$display("  MISMATCH a=%0d b=%0d en=%0b clear=%0b: acc %0d (exp %0d) a_out %0d (exp %0d) b_out %0d (exp %0d)",
						 a, b, e, c, acc, m_acc, a_out, m_a, b_out, m_b);
		end
	endtask

	int corners [0:4];

	initial begin
		$timeformat(-6, 2, "us", 10);
		if (!$value$plusargs("SEED=%d", seed))             seed = 1;
		if (!$value$plusargs("NUM_RANDOM=%d", num_random)) num_random = 2000;
		rng_state = (seed == 0) ? 32'h1 : seed;
		checks = 0; errors = 0;
		corners[0] = -128; corners[1] = -1; corners[2] = 0; corners[3] = 1; corners[4] = 127;
		m_acc = 0; m_a = 0; m_b = 0;

		$display("=== pe testbench: SEED=%0d NUM_RANDOM=%0d ===", seed, num_random);
		a_in = '0; b_in = '0; en = 1'b0; clear = 1'b0;
		resetn = 1'b0;
		repeat (2) @(negedge clock_50);
		resetn = 1'b1;

		// Every corner product, one at a time from a cleared accumulator
		$display("[directed] signed corner products");
		foreach (corners[i])
			foreach (corners[j]) begin
				step(0, 0, 1'b0, 1'b1);                       // clear
				step(corners[i], corners[j], 1'b1, 1'b0);     // single MAC
			end

		// Accumulate the worst case: 4 x (-128 x -128) = 65,536
		$display("[directed] accumulate 4 x (-128 x -128)");
		step(0, 0, 1'b0, 1'b1);
		repeat (4) step(-128, -128, 1'b1, 1'b0);
		if (acc !== 65536) begin
			errors++;
			$display("  ERROR: worst-case sum %0d, expected 65536", acc);
		end

		// en = 0 must hold acc and the forwarded values
		$display("[directed] enable low holds state");
		step(5, 7, 1'b1, 1'b0);
		repeat (3) step(99, -99, 1'b0, 1'b0);

		// clear has priority over en
		$display("[directed] clear overrides enable");
		step(11, 13, 1'b1, 1'b1);

		// Asynchronous reset in the middle of accumulating
		$display("[directed] reset clears everything");
		step(100, 100, 1'b1, 1'b0);
		resetn = 1'b0;
		#1;
		if (acc !== 0 || a_out !== 0 || b_out !== 0) begin
			errors++;
			$display("  ERROR: reset did not clear the PE");
		end
		m_acc = 0; m_a = 0; m_b = 0;
		@(negedge clock_50) resetn = 1'b1;

		// Random steps (clear rarely so the accumulator gets large)
		$display("[random] %0d steps", num_random);
		for (int t = 0; t < num_random; t++) begin
			logic [31:0] r;
			r = rng_next();
			step($signed(r[7:0]), $signed(r[15:8]), r[18:16] != 3'd0, r[24:19] == 6'd0);
		end

		$display("--------------------------------------------------");
		$display("Checks run       : %0d", checks);
		$display("Errors           : %0d", errors);
		if (errors == 0) $display("TEST PASSED");
		else             $display("TEST FAILED");
		$display("--------------------------------------------------");
		$stop;
	end

endmodule
