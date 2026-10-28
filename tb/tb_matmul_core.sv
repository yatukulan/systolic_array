/*
4x4 INT8 Systolic Array
Yatukulan Vivekanandan
Department of Electrical and Computer Engineering
McMaster University
Ontario, Canada
*/

// This is the self-checking testbench for matmul_core
//
//   * Directed tests: zeros, identity, extreme values, sign mixes,
//     start-while-busy, reset in the middle of a run
//   * Randomized tests: NUM_RANDOM matrix pairs from a seeded generator
//   * Reference model: plain nested-loop matrix multiply (behavioural)
//   * Scoreboard: compares all 16 outputs of every test, counts mismatches
//   * Protocol checks: done is a 1-clock pulse, latency is exactly 3N cycles
//
// Plusargs:  +SEED=<n>  +NUM_RANDOM=<n>
// Prints "TEST PASSED" or "TEST FAILED" (parsed by scripts/regress.py).
//
// Written in plain procedural SystemVerilog so it runs unchanged in
// ModelSim/Questa, Verilator and Icarus Verilog.

`timescale 1ns/100ps
`ifndef DISABLE_DEFAULT_NET
`default_nettype none
`endif

module TB;

	parameter N = 4;
	parameter DW = 8;
	parameter AW = 32;
	// Clock cycles from the cycle start is high until done is high:
	// 1 (load) + 1 (clear) + (3N-2) (run) = 3N  -> 12 for N = 4
	parameter EXPECTED_LATENCY = 3*N;
	parameter TIMEOUT_CYCLES = 1000;

	// ---------------- DUT signals ----------------
	logic              clock_50 = 1'b0;
	logic              resetn;
	logic              start;
	logic [N*N*DW-1:0] a_flat, b_flat;
	logic              busy, done;
	logic [N*N*AW-1:0] c_flat;

	always begin
		#10;
		clock_50 = ~clock_50;
	end

		matmul_core #(
		.N(N)
	) UUT (
		.Clock(clock_50),
		.Resetn(resetn),
		.Start(start),
		.A_flat(a_flat),
		.B_flat(b_flat),
		.Busy(busy),
		.Done(done),
		.C_flat(c_flat)
	);

	// ---------------- Test state ----------------
	int A [0:N*N-1];          // A[i*N+k]
	int B [0:N*N-1];          // B[k*N+j]
	int C_ref [0:N*N-1];      // expected result

	int seed, num_random;
	int tests_run, checks_run, mismatches, protocol_errors;

	// ---------------- Seeded random generator (xorshift32) ----------------
	// Used instead of $urandom so a given SEED produces the same matrices
	// in every simulator.
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

	// Random INT8, with extra weight on corner values that catch sign bugs
	function int rand_int8();
		logic [31:0] r;
		r = rng_next();
		case (r[31:29])
			3'd0: return -128;
			3'd1: return 127;
			default: return $signed(r[7:0]);
		endcase
	endfunction

	// ---------------- Reference model ----------------
	task compute_reference();
		for (int i = 0; i < N; i++)
			for (int j = 0; j < N; j++) begin
				int sum;
				sum = 0;
				for (int k = 0; k < N; k++) sum += A[i*N+k] * B[k*N+j];
				C_ref[i*N+j] = sum;
			end
	endtask

	// Pack the test matrices onto the DUT inputs
	task drive_operands();
		for (int idx = 0; idx < N*N; idx++) begin
			a_flat[idx*DW +: DW] = A[idx][DW-1:0];
			b_flat[idx*DW +: DW] = B[idx][DW-1:0];
		end
	endtask

	// ---------------- Scoreboard ----------------
	task check_results(input int test_id);
		for (int idx = 0; idx < N*N; idx++) begin
			int got;
			got = $signed(c_flat[idx*AW +: AW]);
			checks_run++;
			if (got !== C_ref[idx]) begin
				mismatches++;
				if (mismatches <= 10)
					$display("  MISMATCH test %0d C[%0d][%0d]: expected %0d, got %0d",
							 test_id, idx / N, idx % N, C_ref[idx], got);
			end
		end
	endtask

	// ---------------- One complete matrix multiply ----------------
	task run_one(input int test_id);
		int cycles;
		compute_reference();
		drive_operands();

		@(negedge clock_50) start = 1'b1;
		@(negedge clock_50) start = 1'b0;
		cycles = 1;
		while (!done && cycles < TIMEOUT_CYCLES) begin
			@(negedge clock_50);
			cycles++;
		end

		if (!done) begin
			$display("  ERROR test %0d: timeout waiting for done", test_id);
			protocol_errors++;
		end else begin
			if (cycles != EXPECTED_LATENCY) begin
				$display("  ERROR test %0d: latency %0d, expected %0d",
						 test_id, cycles, EXPECTED_LATENCY);
				protocol_errors++;
			end
			check_results(test_id);
			@(negedge clock_50);
			if (done) begin
				$display("  ERROR test %0d: done held high for more than 1 clock", test_id);
				protocol_errors++;
			end
		end
		tests_run++;
	endtask

	task fill(input int a_val, input int b_val);
		for (int idx = 0; idx < N*N; idx++) begin
			A[idx] = a_val;
			B[idx] = b_val;
		end
	endtask

	task fill_random();
		for (int idx = 0; idx < N*N; idx++) begin
			A[idx] = rand_int8();
			B[idx] = rand_int8();
		end
	endtask

	task apply_reset();
		$display("\n*** Asserting the asynchronous reset ***");
		resetn = 1'b0;
		repeat (3) @(negedge clock_50);
		resetn = 1'b1;
		@(negedge clock_50);
	endtask

	// ---------------- Main sequence ----------------
	initial begin
		$timeformat(-6, 2, "us", 10);
		if (!$value$plusargs("SEED=%d", seed))             seed = 1;
		if (!$value$plusargs("NUM_RANDOM=%d", num_random)) num_random = 500;
		rng_state = (seed == 0) ? 32'h1 : seed;

		tests_run = 0; checks_run = 0; mismatches = 0; protocol_errors = 0;

		$display("=== matmul_core testbench: SEED=%0d NUM_RANDOM=%0d ===", seed, num_random);
		start  = 1'b0;
		a_flat = '0;
		b_flat = '0;
		apply_reset();

		// ---- Directed tests ----
		$display("[directed] zeros");                 fill(0, 0);       run_one(0);
		$display("[directed] all max (127 x 127)");   fill(127, 127);   run_one(1);
		$display("[directed] all min (-128 x -128)"); fill(-128, -128); run_one(2);
		$display("[directed] max x min");             fill(127, -128);  run_one(3);

		$display("[directed] identity x random");
		fill_random();
		for (int i = 0; i < N; i++)
			for (int k = 0; k < N; k++) A[i*N+k] = (i == k) ? 1 : 0;
		run_one(4);

		$display("[directed] distinct values 1..16 (catches index/skew bugs)");
		for (int idx = 0; idx < N*N; idx++) begin
			A[idx] = idx + 1;
			B[idx] = -(idx + 1);
		end
		run_one(5);

		$display("[directed] start pulsed while busy must be ignored");
		fill_random();
		compute_reference();
		drive_operands();
		@(negedge clock_50) start = 1'b1;
		@(negedge clock_50) start = 1'b0;
		repeat (3) @(negedge clock_50);
		a_flat = ~a_flat;                 // change operands and pulse start mid-run
		@(negedge clock_50) start = 1'b1;
		@(negedge clock_50) start = 1'b0;
		while (!done) @(negedge clock_50);
		check_results(6);
		tests_run++;
		@(negedge clock_50);

		$display("[directed] reset in the middle of a run, then a clean run");
		fill(5, 7);
		drive_operands();
		@(negedge clock_50) start = 1'b1;
		@(negedge clock_50) start = 1'b0;
		repeat (4) @(negedge clock_50);
		apply_reset();
		if (c_flat !== '0 || busy) begin
			$display("  ERROR: state not cleared by reset");
			protocol_errors++;
		end
		fill_random();
		run_one(7);

		// ---- Randomized tests (back-to-back, no reset between them) ----
		$display("[random] %0d matrix pairs", num_random);
		for (int t = 0; t < num_random; t++) begin
			fill_random();
			run_one(100 + t);
		end

		// ---- Report ----
		$display("--------------------------------------------------");
		$display("Tests run        : %0d", tests_run);
		$display("Outputs checked  : %0d", checks_run);
		$display("Mismatches       : %0d", mismatches);
		$display("Protocol errors  : %0d", protocol_errors);
		if (mismatches == 0 && protocol_errors == 0) $display("TEST PASSED");
		else                                          $display("TEST FAILED");
		$display("--------------------------------------------------");
		$stop;
	end

	// Global watchdog
	initial begin
		#(64'd20 * 64'd2000000);
		$display("TEST FAILED (global timeout)");
		$stop;
	end

endmodule
